import '../widgets/graph_page_chrome.dart';
import '../services/ops_user_service.dart';
import '../services/ops_user_service_factory.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/customer_file.dart';
import '../models/job.dart';
import '../services/customer_files_service.dart';
import '../services/customer_files_service_factory.dart';
import '../services/bugman_portal_service.dart';
import '../services/portal_sign_in.dart';
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
    this.opsUserService,
    super.key,
  });

  static const String routeName = '/new-job';
  static const List<String> serviceTypes = [
    'Inspection',
    'WDIR',
    'ATBS Installation',
    'General Use',
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
  final OpsUserService? opsUserService;

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
  OpsGraphUsers _opsUsers = const OpsGraphUsers();
  String _creatorMode = '__manual__';
  bool _creatorTouched = false;
  bool _creatorsLoading = true;

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
      'contactPhone'
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
    _loadCreators();
  }

  Future<void> _loadCreators() async {
    OpsGraphUsers result;
    try {
      result = await (widget.opsUserService ?? createOpsUserService()).load();
    } catch (_) {
      result = const OpsGraphUsers();
    }
    if (!mounted) return;
    setState(() {
      _opsUsers = result;
      _creatorsLoading = false;
      if (!_creatorTouched &&
          _createdByController.text.isEmpty &&
          result.current != null) {
        _createdByController.text = result.current!.name;
        _creatorMode = result.current!.username;
      } else if (!_creatorTouched) {
        for (final user in result.users) {
          if (user.name == _createdByController.text) {
            _creatorMode = user.username;
          }
        }
      }
    });
  }

  Future<void> _editOptionalContact() async {
    final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _OptionalContactDialog(
            name: _details['contactName']!.text,
            phone: _details['contactPhone']!.text));
    if (!mounted || values == null) return;
    setState(() {
      _details['contactName']!.text = values['name']!;
      _details['contactPhone']!.text = values['phone']!;
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
      'streetAddress': _locationAddressController.text.trim(),
      'state': 'NC',
      'customerType': _customerType,
      'customerLocationId': _selectedLocation?.customerLocationId ?? '',
      'billToId': _selectedLocation?.billToId ?? '',
    };
    final name = details['company']!.isNotEmpty
        ? details['company']!
        : [details['first']!, details['last']!]
            .where((value) => value.isNotEmpty)
            .join(' ');
    final address = [
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.editOnly ? 'Edit Job' : 'New Job'),
            actions: const [OpsBrainHomeButton()]),
        body: GraphPageBackdrop(child:
            SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final contact = GraphFormCard(
              title: 'Contact & Location',
              icon: Icons.person_outline,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.resolutionWarning != null &&
                        !_warningDismissed) ...[
                      _ResolutionWarningBanner(
                          message: widget.resolutionWarning!,
                          onDismiss: () =>
                              setState(() => _warningDismissed = true)),
                      const SizedBox(height: 12)
                    ],
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(
                          label: const Text('Existing Customer'),
                          selected: !_manualEntryOverride,
                          onSelected: (_) => _toggleManualEntry(false)),
                      ChoiceChip(
                          label: const Text('New Customer'),
                          selected: _manualEntryOverride,
                          onSelected: (_) => _toggleManualEntry(true))
                    ]),
                    const SizedBox(height: 12),
                    Text(
                        'Bill To: ${_pestPacBillToController.text.isEmpty ? 'New/Unassigned' : _pestPacBillToController.text} \u00b7 Location: ${_pestPacLocationController.text.isEmpty ? 'New/Unassigned' : _pestPacLocationController.text}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    if (_showingLocationSummary) ..._buildLocationSummary(),
                    if (_showingSearch) ..._buildCustomerSearch(),
                    if (_manualEntryOverride || _selectedLocation != null)
                      ..._buildManualFields(),
                  ]));
          final graphDetails = GraphFormCard(
              title: 'Graph Details',
              icon: Icons.assignment_outlined,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                        key: const ValueKey('job-date-field'),
                        controller: _dateController,
                        readOnly: true,
                        onTap: _pickDate,
                        decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                            suffixIcon: Icon(Icons.edit_calendar_outlined))),
                    const SizedBox(height: 18),
                    Text('Service Type',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final type in NewJobScreen.serviceTypes)
                        ChoiceChip(
                            label: Text(type),
                            selected: _serviceType == type,
                            onSelected: (_) =>
                                setState(() => _serviceType = type))
                    ]),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                        key: ValueKey(
                            'creator-mode-$_creatorMode-${_opsUsers.users.length}'),
                        initialValue: _creatorMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Created By',
                            prefixIcon: Icon(Icons.badge_outlined)),
                        items: [
                          for (final user in _opsUsers.users)
                            DropdownMenuItem(
                                value: user.username,
                                child: Text(user.name,
                                    overflow: TextOverflow.ellipsis)),
                          const DropdownMenuItem(
                              value: '__manual__',
                              child: Text('Enter manually'))
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _creatorTouched = true;
                            _creatorMode = value;
                            if (value != '__manual__') {
                              _createdByController.text = _opsUsers.users
                                  .firstWhere((u) => u.username == value)
                                  .name;
                            }
                          });
                        }),
                    if (_creatorsLoading)
                      const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Loading signed-in user...')),
                    if (_creatorMode == '__manual__') ...[
                      const SizedBox(height: 12),
                      TextField(
                          key: const ValueKey('created-by-manual'),
                          controller: _createdByController,
                          onChanged: (_) => _creatorTouched = true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                              labelText: 'Created By',
                              hintText: 'Enter your name'),
                          onSubmitted: (_) => _createJob()),
                      const SizedBox(height: 8),
                      const Text(
                          'Choose an available OpsBrain user or enter a name manually.',
                          style: TextStyle(fontSize: 12))
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _createJob,
                            icon: Icon(widget.editOnly
                                ? Icons.save_outlined
                                : Icons.arrow_forward),
                            label: Text(widget.editOnly
                                ? 'Save Changes'
                                : 'Create Graph'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52)))),
                  ]));
          return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(children: [
                        GraphPageHero(
                            title: widget.editOnly
                                ? 'Update graph information'
                                : 'Start a New Graph',
                            subtitle:
                                'Customer details, inspection type and the person creating this graph.',
                            compact: true),
                        const SizedBox(height: 20),
                        if (constraints.maxWidth >= 1000 &&
                            MediaQuery.textScalerOf(context).scale(14) < 20)
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: contact),
                                const SizedBox(width: 20),
                                Expanded(child: graphDetails)
                              ])
                        else ...[
                          contact,
                          const SizedBox(height: 20),
                          graphDetails
                        ],
                      ]))));
        }))),
      );

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
          hintText: 'Search name, Bill-To, Location, or addressâ€¦',
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
          child: const Text('Customer not found â€” New Customer'),
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  Widget _detailField(String key, String label,
          {TextInputType? keyboardType}) =>
      TextField(
          controller: _details[key],
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label));

  List<Widget> _buildManualFields() => [
        ResponsiveGraphFields(fullWidthOnNarrow: const {
          3,
          9
        }, children: [
          _detailField('company', 'Company'),
          _detailField('first', 'First Name'),
          _detailField('last', 'Last Name'),
          TextField(
              controller: _locationAddressController,
              decoration: const InputDecoration(labelText: 'Street Address')),
          _detailField('city', 'City'),
          TextField(
              controller: _stateController,
              enabled: false,
              decoration:
                  const InputDecoration(labelText: 'State', hintText: 'NC')),
          _detailField('zip', 'Zip', keyboardType: TextInputType.number),
          _detailField('phone', 'Phone', keyboardType: TextInputType.phone),
          _detailField('email', 'Email',
              keyboardType: TextInputType.emailAddress),
          TextField(
              controller: _locationNameController,
              decoration: const InputDecoration(labelText: 'Location Name')),
        ]),
        const SizedBox(height: 18),
        Text('Customer Type', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final type in const ['Residential', 'Commercial'])
            ChoiceChip(
                label: Text(type),
                selected: _customerType == type,
                onSelected: (_) => setState(() => _customerType = type))
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            key: const ValueKey('optional-contact-button'),
            onPressed: _editOptionalContact,
            icon: const Icon(Icons.person_add_alt),
            label: Text(_details['contactName']!.text.isEmpty &&
                    _details['contactPhone']!.text.isEmpty
                ? '+ Primary/Alternate Contact'
                : 'Edit Primary/Alternate Contact')),
        if (_details['contactName']!.text.isNotEmpty ||
            _details['contactPhone']!.text.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text([
                _details['contactName']!.text,
                _details['contactPhone']!.text
              ].where((s) => s.isNotEmpty).join(' - '))),
      ];

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

class _OptionalContactDialog extends StatefulWidget {
  const _OptionalContactDialog({required this.name, required this.phone});
  final String name, phone;
  @override
  State<_OptionalContactDialog> createState() => _OptionalContactDialogState();
}

class _OptionalContactDialogState extends State<_OptionalContactDialog> {
  late final name = TextEditingController(text: widget.name);
  late final phone = TextEditingController(text: widget.phone);
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Primary/Alternate Contact'),
        content: SingleChildScrollView(
            child: SizedBox(
                width: 520,
                child: ResponsiveGraphFields(children: [
                  TextField(
                      key: const ValueKey('optional-contact-name'),
                      controller: name,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Name')),
                  TextField(
                      key: const ValueKey('optional-contact-phone'),
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Phone Number')),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context,
                  {'name': name.text.trim(), 'phone': phone.text.trim()}),
              child: const Text('Save Contact'))
        ],
      );
}
