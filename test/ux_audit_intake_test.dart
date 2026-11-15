import 'package:bugman_graphs/models/customer_file.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/services/customer_files_service.dart';
import 'package:bugman_graphs/services/bugman_portal_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Lookup implements CustomerFilesService {
  Lookup({this.available = true, this.failure});
  final bool available;
  final Object? failure;
  @override
  bool get isAvailable => available;
  static const location = CustomerLocation(
      billToNumber: '100',
      billToName: 'Linked account',
      locationNumber: '200',
      locationName: 'Linked site',
      locationAddress: '2 Linked Road',
      customerLocationId: 'loc-200',
      billToId: 'bill-100');
  @override
  Future<List<CustomerSearchResult>> searchCustomers(String query) async {
    if (failure != null) throw failure!;
    return [
      const CustomerSearchResult(
          billTo:
              CustomerBillTo(billToNumber: '100', billToName: 'Linked account'),
          location: location)
    ];
  }

  @override
  Future<List<CustomerLocation>> getLocations(String billToNumber) async =>
      [location];
  @override
  Future<CustomerLocation?> getLocation(
          String billToNumber, String locationNumber) async =>
      location;
}

void main() {
  Finder field(String name) => find.widgetWithText(TextField, name);
  String value(WidgetTester t, String name) =>
      t.widget<TextField>(field(name)).controller!.text;
  Future<void> open(WidgetTester t,
      {CustomerFilesService? service, ValueChanged<Job>? created}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1100, 2200);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => NewJobScreen(
                                onCreateJob: created ?? (_) {},
                                returnCreatedJob: true,
                                customerFilesService: service ?? Lookup(),
                                authenticatedNameLoader: () async => null))),
                    child: const Text('Open intake'))))));
    await t.tap(find.text('Open intake'));
    await t.pumpAndSettle();
  }

  testWidgets(
      'manual and linked drafts survive switching without hybrid identity',
      (t) async {
    Job? job;
    await open(t, created: (j) => job = j);
    await t.tap(find.text('New Customer'));
    await t.pumpAndSettle();
    await t.enterText(field('Company'), 'Manual draft');
    await t.enterText(field('Street Address'), '1 Draft Lane');
    await t.enterText(field('Phone'), '555-0101');
    await t.tap(find.text('Existing Customer'));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const ValueKey('customer-search-field')), 'Linked');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    await t.tap(find.text('Linked account — Linked site'));
    await t.pumpAndSettle();
    await t.tap(find.text('New Customer'));
    await t.pumpAndSettle();
    expect(value(t, 'Company'), 'Manual draft');
    expect(value(t, 'Street Address'), '1 Draft Lane');
    expect(value(t, 'Phone'), '555-0101');
    await t.tap(find.text('Existing Customer'));
    await t.pumpAndSettle();
    expect(find.text('Customer File selected'), findsOneWidget);
    await t.tap(find.text('Create Graph'));
    await t.pumpAndSettle();
    expect(job!.pestPacBillToNumber, '100');
    expect(job!.pestPacLocationNumber, '200');
    expect(job!.customerName, 'Linked account');
    expect(job!.intakeDetails['phone'], isEmpty);
    expect(find.byType(NewJobScreen), findsNothing);
  });
  testWidgets('dirty intake Back can keep editing then explicitly discard',
      (t) async {
    await open(t, service: Lookup(available: false));
    await t.enterText(field('Company'), 'Keep my draft');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Discard graph information?'), findsOneWidget);
    await t.tap(find.text('Keep editing'));
    await t.pumpAndSettle();
    expect(value(t, 'Company'), 'Keep my draft');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Discard information'));
    await t.pumpAndSettle();
    expect(find.byType(NewJobScreen), findsNothing);
  });
  testWidgets('untouched intake Back does not ask to discard', (t) async {
    await open(t);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(NewJobScreen), findsNothing);
  });
  testWidgets('unavailable lookup explains fallback and retains manual input',
      (t) async {
    Job? job;
    await open(t, service: Lookup(available: false), created: (j) => job = j);
    await t.enterText(field('Company'), 'Offline draft');
    await t.tap(find.text('Existing Customer'));
    await t.pumpAndSettle();
    expect(find.textContaining('lookup is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-search-field')), findsNothing);
    await t.tap(find.text('Use New Customer'));
    await t.pumpAndSettle();
    expect(value(t, 'Company'), 'Offline draft');
    await t.tap(find.text('Create Graph'));
    await t.pumpAndSettle();
    expect(job!.pestPacBillToNumber, isEmpty);
    expect(job!.pestPacLocationNumber, isEmpty);
  });
  for (final error in [
    const PortalAuthenticationException('https://ops.holloman-ext.com/'),
    StateError('offline')
  ]) {
    testWidgets('lookup failure preserves manual draft: ${error.runtimeType}',
        (t) async {
      await open(t, service: Lookup(failure: error));
      await t.tap(find.text('New Customer'));
      await t.pumpAndSettle();
      await t.enterText(field('Company'), 'Unaffected draft');
      await t.tap(find.text('Existing Customer'));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const ValueKey('customer-search-field')), 'Linked');
      await t.pump(const Duration(milliseconds: 350));
      await t.pumpAndSettle();
      expect(
          find.textContaining(error is PortalAuthenticationException
              ? 'Sign in to OpsBrain in a new tab'
              : 'Customer search is unavailable'),
          findsOneWidget);
      await t.tap(find.text('New Customer'));
      await t.pumpAndSettle();
      expect(value(t, 'Company'), 'Unaffected draft');
    });
  }
}
