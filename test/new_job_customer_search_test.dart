import 'dart:async';
import 'package:bugman_graphs/models/customer_file.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/services/customer_files_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<_JobCapture> pumpNewJobScreen(
    WidgetTester tester, {
    required CustomerFilesService service,
    CustomerLocation? preselectedLocation,
    String? resolutionWarning,
    Future<String?> Function()? authenticatedNameLoader,
  }) async {
    final capture = _JobCapture();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NewJobScreen(
          onCreateJob: (job) => capture.job = job,
          customerFilesService: service,
          preselectedLocation: preselectedLocation,
          resolutionWarning: resolutionWarning,
          authenticatedNameLoader: authenticatedNameLoader,
        ),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (context) => const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capture;
  }

  testWidgets('tapping selected New Customer preserves entered fields',
      (tester) async {
    final capture = await pumpNewJobScreen(tester,
        service: _FakeCustomerFilesService(results: const []));
    await tester.tap(find.widgetWithText(ChoiceChip, 'New Customer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Company'), 'Draft company');
    await tester.tap(find.text('+ Add Contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primary'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '555-0100');
    await tester.tap(find.widgetWithText(ChoiceChip, 'New Customer'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Company'))
            .controller!
            .text,
        'Draft company');
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();
    expect(capture.job!.customerName, 'Draft company');
    expect(capture.job!.intakeDetails['phone'], '555-0100');
  });

  testWidgets('tapping selected Existing Customer preserves linked identity',
      (tester) async {
    final capture = await pumpNewJobScreen(tester,
        service: _FakeCustomerFilesService(results: const []),
        preselectedLocation: const CustomerLocation(
            billToNumber: '100',
            billToName: 'Selected company',
            locationNumber: '990001',
            locationName: 'Main Office',
            locationAddress: '1 Main Street'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Existing Customer'));
    await tester.pumpAndSettle();
    expect(find.text('Customer File selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-search-field')), findsNothing);
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();
    expect(capture.job!.pestPacBillToNumber, '100');
    expect(capture.job!.pestPacLocationNumber, '990001');
    expect(capture.job!.customerName, 'Selected company');
  });

  testWidgets(
      'existing customer must be selected; new customer can stay unnamed',
      (tester) async {
    final capture = await pumpNewJobScreen(tester,
        service: _FakeCustomerFilesService(results: const []));
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();
    expect(capture.job, isNull);
    expect(find.text('Select an existing customer or choose New Customer.'),
        findsOneWidget);
    await tester.tap(find.text('New Customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Graph'));
    await tester.pumpAndSettle();
    expect(capture.job!.displayName, 'Untitled Job');
    expect(capture.job!.pestPacBillToNumber, isEmpty);
    expect(capture.job!.pestPacLocationNumber, isEmpty);
  });

  testWidgets(
      'short query clears stale lookup and sign in keeps entered search',
      (tester) async {
    final pending = Completer<List<CustomerSearchResult>>();
    final service = _FakeCustomerFilesService(results: const [])
      ..response = pending.future;
    await pumpNewJobScreen(tester, service: service);
    final search = find.byKey(const ValueKey('customer-search-field'));
    await tester.enterText(search, '990001');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(search, '9');
    pending.complete(const [
      CustomerSearchResult(
          billTo:
              CustomerBillTo(billToNumber: '100', billToName: 'Stale result'),
          location: CustomerLocation(
              billToNumber: '100',
              billToName: 'Stale result',
              locationNumber: '990001',
              locationName: 'Old location'))
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Stale result'), findsNothing);
    service.response = null;
    service.failure =
        const PortalAuthenticationException('https://ops.holloman-ext.com/');
    await tester.enterText(search, '990001');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in to OpsBrain'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, '990001');
    expect(find.byType(NewJobScreen), findsOneWidget);
  });

  testWidgets(
    'searching shows matching Customer Files and selecting one locks the identity fields',
    (tester) async {
      final service = _FakeCustomerFilesService(results: [
        const CustomerSearchResult(
          billTo: CustomerBillTo(billToNumber: '100', billToName: 'Acme Co'),
          location: CustomerLocation(
            billToNumber: '100',
            billToName: 'Acme Co',
            locationNumber: '1',
            locationName: 'Acme Co - Main Office',
            locationAddress: '1 Main St',
          ),
        ),
      ]);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
          ),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            builder: (context) => const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('customer-search-field')), findsOneWidget);
      // No manual identity fields shown before a customer is selected.
      expect(find.widgetWithText(TextField, 'PestPac Bill-To #'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('customer-search-field')),
        'Acme',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(service.lastQuery, 'Acme');
      expect(find.text('Acme Co — Acme Co - Main Office'), findsOneWidget);

      await tester.tap(find.text('Acme Co — Acme Co - Main Office'));
      await tester.pumpAndSettle();

      // The identity fields are now shown locked in a summary card, not as
      // editable TextFields.
      expect(find.text('Customer File selected'), findsOneWidget);
      expect(find.text('Acme Co - Main Office'), findsNWidgets(2));
      expect(find.text('1 Main St'), findsNWidgets(2));
      expect(find.text('Bill-To # 100 · Location # 1'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'PestPac Bill-To #'), findsNothing);

      await tester.tap(find.text('Create Graph'));
      await tester.pump();

      // Nothing else to assert on navigation here; confirm identity made it
      // onto the created Job via the callback in the wrapper below.
    },
  );

  testWidgets('known identity fills and locks Created By', (tester) async {
    await pumpNewJobScreen(
      tester,
      service: _FakeCustomerFilesService(results: const []),
      authenticatedNameLoader: () async => 'Field Technician',
    );

    final createdBy = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Created By'),
    );
    expect(createdBy.controller!.text, 'Field Technician');
    expect(createdBy.readOnly, isTrue);
  });

  testWidgets('unavailable identity preserves manual Created By fallback',
      (tester) async {
    await pumpNewJobScreen(
      tester,
      service: _FakeCustomerFilesService(results: const []),
      authenticatedNameLoader: () async => null,
    );

    final finder = find.widgetWithText(TextField, 'Created By');
    expect(tester.widget<TextField>(finder).readOnly, isFalse);
    await tester.enterText(finder, 'Manual Technician');
    expect(
        tester.widget<TextField>(finder).controller!.text, 'Manual Technician');
  });

  testWidgets(
    'created job carries the selected Customer File PestPac identifiers',
    (tester) async {
      final service = _FakeCustomerFilesService(results: [
        const CustomerSearchResult(
          billTo: CustomerBillTo(billToNumber: '100', billToName: 'Acme Co'),
          location: CustomerLocation(
            billToNumber: '100',
            billToName: 'Acme Co',
            locationNumber: '1',
            locationName: 'Acme Co - Main Office',
            locationAddress: '1 Main St',
          ),
        ),
      ]);

      final capture = await pumpNewJobScreen(tester, service: service);
      // Trigger a search + selection, then submit.
      await tester.enterText(
        find.byKey(const ValueKey('customer-search-field')),
        'Acme',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Co — Acme Co - Main Office'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Graph'));
      await tester.pump();

      final job = capture.job;
      expect(job, isNotNull);
      expect(job!.customerName, 'Acme Co');
      expect(job.intakeDetails['locationName'], 'Acme Co - Main Office');
      expect(job.serviceAddress, '1 Main St');
      expect(job.pestPacBillToNumber, '100');
      expect(job.pestPacLocationNumber, '1');
    },
  );

  testWidgets(
    '"Change" clears the selected customer and reopens search',
    (tester) async {
      final service = _FakeCustomerFilesService(results: const []);
      const location = CustomerLocation(
        billToNumber: '200',
        billToName: 'Beta LLC',
        locationNumber: '2',
        locationName: 'Beta LLC - Warehouse',
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
            preselectedLocation: location,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customer File selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('change-customer-button')));
      await tester.pumpAndSettle();

      expect(find.text('Customer File selected'), findsNothing);
      expect(
          find.byKey(const ValueKey('customer-search-field')), findsOneWidget);
    },
  );

  testWidgets(
    'New Customer keeps identifiers unassigned and permits contact entry',
    (tester) async {
      final service = _FakeCustomerFilesService(results: const []);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('manual-entry-toggle')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'PestPac Bill-To #'), findsNothing);
      expect(
          find.widgetWithText(TextField, 'PestPac Location #'), findsNothing);
      expect(find.widgetWithText(TextField, 'Company'), findsOneWidget);
      expect(find.text('Bill To: New/Unassigned · Location: New/Unassigned'),
          findsOneWidget);
    },
  );

  testWidgets(
    'a resolution warning banner is shown when a deep-linked customer could not be resolved',
    (tester) async {
      final service = _FakeCustomerFilesService(results: const []);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
            resolutionWarning:
                'Bill-To 999 / Location 1 was not found in Ops Brain.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Bill-To 999 / Location 1 was not found in Ops Brain.'),
        findsOneWidget,
      );
      // Still falls through to the normal search flow, not manual entry.
      expect(
          find.byKey(const ValueKey('customer-search-field')), findsOneWidget);
    },
  );

  testWidgets(
    'editing an existing job never shows the customer search flow',
    (tester) async {
      final service = _FakeCustomerFilesService(results: const []);
      final job = Job(
        customerName: 'Existing Customer',
        serviceAddress: '5 Old Rd',
        pestPacLocationNumber: '9',
        pestPacBillToNumber: '10',
        serviceType: 'Inspection',
        createdBy: 'Tester',
        createdDate: DateTime(2026, 1, 1),
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
            initialJob: job,
            editOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('customer-search-field')), findsNothing);
      expect(find.widgetWithText(TextField, 'Location Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'PestPac Bill-To #'), findsNothing);
    },
  );

  testWidgets(
    'an unavailable Customer Files service falls back to manual entry only',
    (tester) async {
      final service = _FakeCustomerFilesService(
        results: const [],
        available: false,
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: NewJobScreen(
            onCreateJob: (_) {},
            customerFilesService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('customer-search-field')), findsNothing);
      expect(find.widgetWithText(TextField, 'Location Name'), findsOneWidget);
    },
  );
}

class _JobCapture {
  Job? job;
}

class _FakeCustomerFilesService implements CustomerFilesService {
  _FakeCustomerFilesService({required this.results, this.available = true});

  final List<CustomerSearchResult> results;
  final bool available;
  String? lastQuery;
  Future<List<CustomerSearchResult>>? response;
  Object? failure;

  @override
  bool get isAvailable => available;

  @override
  Future<List<CustomerSearchResult>> searchCustomers(String query) async {
    lastQuery = query;
    if (failure != null) throw failure!;
    if (response != null) return response!;
    return results;
  }

  @override
  Future<List<CustomerLocation>> getLocations(String billToNumber) async =>
      results
          .where((result) => result.billTo.billToNumber == billToNumber)
          .map((result) => result.location)
          .toList();

  @override
  Future<CustomerLocation?> getLocation(
    String billToNumber,
    String locationNumber,
  ) async {
    for (final result in results) {
      if (result.location.billToNumber == billToNumber &&
          result.location.locationNumber == locationNumber) {
        return result.location;
      }
    }
    return null;
  }
}
