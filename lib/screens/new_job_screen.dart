import 'dart:async';

import 'package:flutter/material.dart';

import '../models/customer_file.dart';
import '../models/job.dart';
import '../services/customer_files_service.dart';
import '../services/customer_files_service_factory.dart';
import '../services/bugman_portal_service.dart';
import '../services/portal_sign_in.dart';
import '../services/authenticated_identity.dart';
import '../widgets/ops_brain_home_button.dart';
import 'graph_canvas_screen.dart';

class NewJobScreen extends StatefulWidget {
  const NewJobScreen({
    required this.onCreateJob,
    this.initialJob,
    this.editOnly = false,
    this.preselectedLocation,
    this.resolutionWarning,
    this.customerFilesService,
    this.authenticatedNameLoader,
    super.key,
  });

  static const String routeName = '/new-job';
  static const List<String> serviceTypes = [
    'Inspection',
    'WDIR',
    'ATBS Installation',
    'General Use',
    'Termite Treatment',
  ];

  final ValueChanged<Job> onCreateJob;
  final Job? initialJob;
  final bool editOnly;

  /// A Bill-To/Location already resolved against Ops Brain (e.g. by a
  /// Sales Brain "Create New" deep link). When set, the customer identity
  /// fields are pre-filled and locked instead of requiring a fresh search.
  final CustomerLocation? preselectedLocation;

  /// Set when a deep link supplied a Bill-To/Location that could not be
  /// resolved against Ops Brain (not found, or the lookup failed). Shown
  /// as a warning banner; the technician must search or enter manually --
  /// the unresolved identifiers themselves are never used.
  final String? resolutionWarning;

  /// Overrides the Customer Files service used for search. Exposed for
  /// tests; production code should leave this null so the real
  /// Ops-Brain-backed implementation is used.
  final CustomerFilesService? customerFilesService;
  final Future<String?> Function()? authenticatedNameLoader;

  @override
  State<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends State<NewJobScreen> {
  final _locationNameController = TextEditingController();
  final _locationAddressController = TextEditingController();
  final _pestPacLocationController = TextEditingController();
  final _pestPacBillToController = TextEditingController();
  final _createdByController = TextEditingController();
  final _searchController = TextEditingController();
  final _stateController = TextEditingController(text: 'NC');
  late final TextEditingController _dateController;
  late DateTime _createdDate;
  late final CustomerFilesService _customerFilesService;

  String _serviceType = 'Inspection';
  bool _authenticatedCreator = false;
  bool _primaryContactVisible = false;
  bool _alternateContactVisible = false;

  CustomerLocation? _selectedLocation;
  bool _manualEntryOverride = false;
  int _searchRequest = 0;
  String? _signInUrl;
  String _customerType = '';
  final _details = <String, TextEditingController>{
    for (final key in [
      'company',
      'first',
      'last',
      'city',
      'zip',
      'phone',
      'email',
      'contactName',
      'contactPhone',
      'primaryContactName',
      'contactEmail',
    ])
      key: TextEditingController(),
  };
  bool _searching = false;
  String? _searchError;
  List<CustomerSearchResult> _searchResults = const [];
  Timer? _searchDebounce;
  bool _warningDismissed = false;

  bool get _searchFlowEnabled => _customerFilesService.isAvailable;

  bool get _showingLocationSummary =>
      _searchFlowEnabled && !_manualEntryOverride && _selectedLocation != null;

  bool get _showingSearch =>
      _searchFlowEnabled && !_manualEntryOverride && _selectedLocation == null;

  @override
  void initState() {
    super.initState();
    _customerFilesService =
        widget.customerFilesService ?? createCustomerFilesService();
    final initialJob = widget.initialJob;
    _manualEntryOverride = initialJob != null
        ? initialJob.pestPacBillToNumber.isEmpty ||
            initialJob.pestPacLocationNumber.isEmpty
        : !_customerFilesService.isAvailable;
    _createdDate = DateUtils.dateOnly(
      initialJob?.createdDate ?? DateTime.now(),
    );
    _dateController = TextEditingController(text: _formatDate(_createdDate));
    if (initialJob != null) {
      final details = initialJob.intakeDetails;
      for (final entry in _details.entries) {
        entry.value.text = details[entry.key] ?? '';
      }
      if (details.isEmpty) _details['company']!.text = initialJob.customerName;
      _customerType = details['customerType'] ?? '';
      _locationNameController.text =
          details['locationName'] ?? initialJob.customerName;
      _locationAddressController.text = initialJob.serviceAddress;
      _pestPacLocationController.text = initialJob.pestPacLocationNumber;
      _pestPacBillToController.text = initialJob.pestPacBillToNumber;
      _createdByController.text = initialJob.createdBy;
      if (initialJob.pestPacBillToNumber.isNotEmpty &&
          initialJob.pestPacLocationNumber.isNotEmpty) {
        _selectedLocation = CustomerLocation(
          billToNumber: initialJob.pestPacBillToNumber,
          billToName: initialJob.customerName,
          locationNumber: initialJob.pestPacLocationNumber,
          locationName: _locationNameController.text,
          locationAddress: initialJob.serviceAddress,
          customerLocationId: details['customerLocationId'] ?? '',
          billToId: details['billToId'] ?? '',
        );
      }
      _locationAddressController.text =
          details['streetAddress'] ?? initialJob.serviceAddress;
      _serviceType = NewJobScreen.serviceTypes.contains(initialJob.serviceType)
          ? initialJob.serviceType
          : 'Inspection';
    }
    final preselected = widget.preselectedLocation;
    if (preselected != null) {
      _manualEntryOverride = false;
      _selectedLocation = preselected;
      _applyLocation(preselected);
    }
    _restoreContactVisibility();
    _loadCreator();
  }

  void _restoreContactVisibility() {
    _primaryContactVisible = ['phone', 'email', 'primaryContactName']
        .any((key) => _details[key]!.text.isNotEmpty);
    _alternateContactVisible = ['contactName', 'contactPhone', 'contactEmail']
        .any((key) => _details[key]!.text.isNotEmpty);
  }

  Future<void> _loadCreator() async {
    final name =
        await (widget.authenticatedNameLoader ?? loadAuthenticatedName)();
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() {
      _authenticatedCreator = true;
      if (widget.initialJob == null ||
          _createdByController.text.trim().isEmpty) {
        _createdByController.text = name.trim();
      }
    });
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    _locationAddressController.dispose();
    _pestPacLocationController.dispose();
    _pestPacBillToController.dispose();
    _createdByController.dispose();
    _dateController.dispose();
    _searchController.dispose();
    _stateController.dispose();
    _searchDebounce?.cancel();
    for (final controller in _details.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyLocation(CustomerLocation location) {
    for (final controller in _details.values) {
      controller.clear();
    }
    // Bill-To name is the available company/account name. Do not attempt to
    // split it into first/last name fields when the source is not structured.
    _details['company']!.text = location.billToName;
    _details['phone']!.text = location.phone;
    _details['email']!.text = location.email;
    _customerType = '';
    _locationNameController.text = location.locationName.isNotEmpty
        ? location.locationName
        : location.billToName;
    _locationAddressController.text = location.locationAddress ?? '';
    _pestPacLocationController.text = location.locationNumber;
    _pestPacBillToController.text = location.billToNumber;
    final previous = widget.initialJob;
    if (previous != null &&
        previous.pestPacBillToNumber == location.billToNumber &&
        previous.pestPacLocationNumber == location.locationNumber) {
      for (final entry in _details.entries) {
        final saved = previous.intakeDetails[entry.key];
        if (saved != null && saved.isNotEmpty) entry.value.text = saved;
      }
      _locationAddressController.text =
          previous.intakeDetails['streetAddress'] ??
              _locationAddressController.text;
      _customerType = previous.intakeDetails['customerType'] ?? '';
    }
    _restoreContactVisibility();
  }

  void _clearLocationFields() {
    for (final controller in _details.values) {
      controller.clear();
    }
    _customerType = '';
    _locationNameController.clear();
    _locationAddressController.clear();
    _pestPacLocationController.clear();
    _pestPacBillToController.clear();
    _primaryContactVisible = false;
    _alternateContactVisible = false;
  }

  void _selectLocation(CustomerLocation location) {
    _searchDebounce?.cancel();
    _searchRequest += 1;
    setState(() {
      _selectedLocation = location;
      _applyLocation(location);
      _searchResults = const [];
      _searchController.clear();
      _searchError = null;
    });
  }

  void _changeCustomer() {
    _searchDebounce?.cancel();
    _searchRequest += 1;
    setState(() {
      _selectedLocation = null;
      _clearLocationFields();
      _searchResults = const [];
      _searchController.clear();
      _searchError = null;
    });
  }

  void _toggleManualEntry(bool manual) {
    if (manual == _manualEntryOverride) return;
    _searchDebounce?.cancel();
    _searchRequest += 1;
    setState(() {
      _manualEntryOverride = manual;
      _selectedLocation = null;
      _clearLocationFields();
      _searchResults = const [];
      _searchController.clear();
      _searchError = null;
      _signInUrl = null;
      _searching = false;
    });
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    setState(() {
      _searchResults = const [];
      _searching = false;
      _searchError = null;
      _signInUrl = null;
    });
    if (query.trim().length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(query.trim(), request);
    });
  }

  Future<void> _runSearch(String query, int request) async {
    setState(() {
      _searching = true;
    });
    try {
      final results = await _customerFilesService.searchCustomers(query);
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
        if (error is PortalAuthenticationException) {
          _signInUrl = error.signInUrl;
          _searchError =
              'Sign in to OpsBrain in a new tab, then retry your search here.';
        } else {
          _searchError = 'Customer search is unavailable. Try again.';
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _createdDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      _createdDate = DateUtils.dateOnly(selectedDate);
      _dateController.text = _formatDate(_createdDate);
    });
  }

  void _createJob() {
    if (!_manualEntryOverride && _selectedLocation == null) {
      setState(() {
        _searchError = 'Select an existing customer or choose New Customer.';
      });
      return;
    }
    final details = <String, String>{
      ...?widget.initialJob?.intakeDetails,
      for (final entry in _details.entries) entry.key: entry.value.text.trim(),
      'leadType': _manualEntryOverride ? 'New Customer' : 'Existing Customer',
      'locationName': _locationNameController.text.trim(),
      'streetAddress': _selectedLocation == null
          ? _locationAddressController.text.trim()
          : '',
      'locationAddress': _selectedLocation == null
          ? ''
          : _locationAddressController.text.trim(),
      'state': 'NC',
      'customerType': _customerType,
      'customerLocationId': _selectedLocation?.customerLocationId ?? '',
      'billToId': _selectedLocation?.billToId ?? '',
    };
    final name = _selectedLocation != null
        ? _details['company']!.text.trim()
        : details['company']!.isNotEmpty
            ? details['company']!
            : [details['first']!, details['last']!]
                .where((value) => value.isNotEmpty)
                .join(' ');
    final address = _selectedLocation != null
        ? _locationAddressController.text.trim()
        : [
            details['streetAddress']!,
            details['city']!,
            if (details['city']!.isNotEmpty || details['zip']!.isNotEmpty) 'NC',
            details['zip']!
          ].where((value) => value.isNotEmpty).join(', ');
    final job = Job(
      intakeDetails: details,
      id: widget.initialJob?.id,
      customerName: name,
      serviceAddress: address,
      pestPacLocationNumber: _pestPacLocationController.text.trim(),
      pestPacBillToNumber: _pestPacBillToController.text.trim(),
      serviceType: _serviceType,
      createdBy: _createdByController.text.trim(),
      createdDate: _createdDate,
    );

    widget.onCreateJob(job);

    if (widget.editOnly) {
      Navigator.of(context).pop(job);
      return;
    }

    Navigator.of(context).pushReplacementNamed(
      GraphCanvasScreen.routeName,
      arguments: job,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editOnly ? 'Edit Job' : 'New Job'),
        actions: const [OpsBrainHomeButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.resolutionWarning != null && !_warningDismissed)
              _ResolutionWarningBanner(
                message: widget.resolutionWarning!,
                onDismiss: () => setState(() => _warningDismissed = true),
              ),
            if (widget.resolutionWarning != null && !_warningDismissed)
              const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('Existing Customer'),
                  selected: !_manualEntryOverride,
                  onSelected: (_) => _toggleManualEntry(false)),
              ChoiceChip(
                  label: const Text('New Customer'),
                  selected: _manualEntryOverride,
                  onSelected: (_) => _toggleManualEntry(true)),
            ]),
            const SizedBox(height: 12),
            Text(
                'Bill To: ${_pestPacBillToController.text.isEmpty ? 'New/Unassigned' : _pestPacBillToController.text} · Location: ${_pestPacLocationController.text.isEmpty ? 'New/Unassigned' : _pestPacLocationController.text}'),
            const SizedBox(height: 12),
            if (_showingLocationSummary) ..._buildLocationSummary(),
            if (_showingSearch) ..._buildCustomerSearch(),
            if (_manualEntryOverride || _selectedLocation != null)
              ..._buildManualFields(),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('job-date-field'),
              controller: _dateController,
              readOnly: true,
              onTap: _pickDate,
              decoration: const InputDecoration(
                labelText: 'Date',
                prefixIcon: Icon(Icons.calendar_today_outlined),
                suffixIcon: Icon(Icons.edit_calendar_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _serviceType,
              decoration: const InputDecoration(
                labelText: 'Service Type',
                prefixIcon: Icon(Icons.bug_report_outlined),
              ),
              items: NewJobScreen.serviceTypes
                  .map(
                    (serviceType) => DropdownMenuItem(
                      value: serviceType,
                      child: Text(serviceType),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _serviceType = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _createdByController,
              readOnly: _authenticatedCreator,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Created By',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onSubmitted: (_) => _createJob(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _createJob,
              icon: Icon(
                  widget.editOnly ? Icons.save_outlined : Icons.arrow_forward),
              label: Text(widget.editOnly ? 'Save Changes' : 'Create Graph'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLocationSummary() {
    final location = _selectedLocation!;
    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Customer File selected',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('change-customer-button'),
                    onPressed: _changeCustomer,
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                location.locationName.isNotEmpty
                    ? location.locationName
                    : location.billToName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if ((location.locationAddress ?? '').isNotEmpty)
                Text(location.locationAddress!),
              const SizedBox(height: 4),
              Text(
                'Bill-To # ${location.billToNumber} · Location # ${location.locationNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildCustomerSearch() {
    return [
      TextField(
        key: const ValueKey('customer-search-field'),
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          labelText: 'Find Customer',
          hintText: 'Search name, Bill-To, Location, or address…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
      const SizedBox(height: 8),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _searchError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_signInUrl != null)
        TextButton.icon(
            onPressed: () => openPortalSignIn(_signInUrl!),
            icon: const Icon(Icons.login),
            label: const Text('Sign in to OpsBrain')),
      if (_searchResults.isNotEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              key: const ValueKey('customer-search-results'),
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final location = result.location;
                return ListTile(
                  title: Text(location.displayLabel),
                  subtitle: Text(
                    [
                      if ((location.locationAddress ?? '').isNotEmpty)
                        location.locationAddress!,
                      'Bill-To # ${location.billToNumber} · Location # ${location.locationNumber}',
                    ].join('\n'),
                  ),
                  isThreeLine: (location.locationAddress ?? '').isNotEmpty,
                  onTap: () => _selectLocation(location),
                );
              },
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('manual-entry-toggle'),
          onPressed: () => _toggleManualEntry(true),
          child: const Text('Customer not found — New Customer'),
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  Widget _detailField(String key, String label,
          {TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: _details[key],
            keyboardType: keyboardType,
            decoration: InputDecoration(labelText: label)),
      );

  List<Widget> _buildManualFields() => [
        Text('Location Fields', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _detailField('company', 'Company'),
        Row(children: [
          Expanded(child: _detailField('first', 'First Name')),
          const SizedBox(width: 12),
          Expanded(child: _detailField('last', 'Last Name'))
        ]),
        TextField(
            controller: _locationAddressController,
            decoration: InputDecoration(
                labelText: _selectedLocation == null
                    ? 'Street Address'
                    : 'Location Address')),
        const SizedBox(height: 12),
        _detailField('city', 'City'),
        TextField(
            controller: _stateController,
            enabled: false,
            decoration:
                const InputDecoration(labelText: 'State', hintText: 'NC')),
        const SizedBox(height: 12),
        _detailField('zip', 'Zip', keyboardType: TextInputType.number),
        if (_primaryContactVisible) _contactCard(primary: true),
        if (_alternateContactVisible) _contactCard(primary: false),
        Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<bool>(
                tooltip: 'Add Contact',
                onSelected: (primary) => setState(() {
                      if (primary) {
                        _primaryContactVisible = true;
                      } else {
                        _alternateContactVisible = true;
                      }
                    }),
                itemBuilder: (_) => [
                      PopupMenuItem(
                          value: true,
                          enabled: !_primaryContactVisible,
                          child: const Text('Primary')),
                      PopupMenuItem(
                          value: false,
                          enabled: !_alternateContactVisible,
                          child: const Text('Alternate')),
                    ],
                child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('+ Add Contact')))),
        DropdownButtonFormField<String>(
            key: ValueKey('customer-type-$_customerType'),
            initialValue: _customerType,
            decoration: const InputDecoration(labelText: 'Customer Type'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Select Customer Type')),
              DropdownMenuItem(
                  value: 'Residential', child: Text('Residential')),
              DropdownMenuItem(value: 'Commercial', child: Text('Commercial'))
            ],
            onChanged: (value) => setState(() {
                  _customerType = value ?? '';
                })),
        const SizedBox(height: 12),
        TextField(
            controller: _locationNameController,
            decoration: const InputDecoration(labelText: 'Location Name')),
      ];

  Widget _contactCard({required bool primary}) {
    final keys = primary
        ? ['primaryContactName', 'phone', 'email']
        : ['contactName', 'contactPhone', 'contactEmail'];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(
                        primary ? 'Primary contact' : 'Alternate contact')),
                IconButton(
                    tooltip: primary
                        ? 'Remove primary contact'
                        : 'Remove alternate contact',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                          for (final key in keys) {
                            _details[key]!.clear();
                          }
                          if (primary) {
                            _primaryContactVisible = false;
                          } else {
                            _alternateContactVisible = false;
                          }
                        }))
              ]),
              _detailField(keys[0], primary ? 'Name' : 'Contact Name'),
              _detailField(keys[1], primary ? 'Phone' : 'Contact Phone',
                  keyboardType: TextInputType.phone),
              _detailField(keys[2], primary ? 'Email' : 'Contact Email',
                  keyboardType: TextInputType.emailAddress),
            ])));
  }

  static String _formatDate(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';
}

class _ResolutionWarningBanner extends StatelessWidget {
  const _ResolutionWarningBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
