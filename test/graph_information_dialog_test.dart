import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/screens/graph_canvas_screen.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/models/graph_document.dart';
import 'support/crowded_canvas_fixture.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
void main() {
  for (final size in [const Size(320, 568), const Size(1400, 900)]) {
    testWidgets('graph information modal save/cancel preserves canvas at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final document = crowdedCanvasFixture();
      document.updateCustomer(const GraphCustomerInfo(
          name: 'Synthetic customer',
          serviceAddress: 'Synthetic training site',
          pestPacBillToNumber: 'TEST-BILL',
          pestPacLocationNumber: 'TEST-LOC',
          serviceType: 'Inspection',
          createdBy: 'Regression fixture',
          intakeDetails: {
            'company': 'Synthetic customer',
            'leadType': 'Existing Customer',
            'streetAddress': '',
            'locationAddress': 'Synthetic training site',
            'locationName': 'Synthetic location',
            'customerLocationId': 'TEST-LOCATION-ID',
            'billToId': 'TEST-BILL-ID',
          }));
      final original = document.toJson();
      await tester
          .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
      await tester.pumpAndSettle();
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = viewer.transformationController!.value.clone();
      await tester.tap(find.byTooltip('Edit Graph Information'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
          tester.widget<TextField>(field('Location Address')).controller!.text,
          'Synthetic training site');
      await tester.ensureVisible(field('Company'));
      await tester.enterText(field('Company'), 'Changed synthetic customer');
      await tester.tap(find.byTooltip('Cancel edits'));
      await tester.pumpAndSettle();
      expect(document.toJson(), original);
      expect(viewer.transformationController!.value, matrix);
      await tester.tap(find.byTooltip('Edit Graph Information'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Company'));
      expect(tester.widget<TextField>(field('Company')).controller!.text,
          'Synthetic customer');
      await tester.enterText(field('Company'),
          'A long synthetic customer name for metadata regression coverage');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Save Changes'), 300,
          scrollable: find
              .descendant(
                  of: find.byType(NewJobScreen),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(document.customer.name, startsWith('A long synthetic customer'));
      expect(document.customer.pestPacBillToNumber, 'TEST-BILL');
      expect(document.customer.pestPacLocationNumber, 'TEST-LOC');
      expect(document.customer.serviceAddress, 'Synthetic training site');
      expect(document.customer.intakeDetails['locationAddress'],
          'Synthetic training site');
      expect(document.customer.intakeDetails['customerLocationId'],
          'TEST-LOCATION-ID');
      expect(document.customer.intakeDetails['billToId'], 'TEST-BILL-ID');
      expect(document.createdAt.toIso8601String(), original['createdAt']);
      expect(document.toJson()['graphObjects'], original['graphObjects']);
      expect(document.toJson()['traces'], original['traces']);
      expect(viewer.transformationController!.value, matrix);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Edit Graph Information'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Company'));
      expect(tester.widget<TextField>(field('Company')).controller!.text,
          document.customer.name);
      await tester.tap(find.byTooltip('Cancel edits'));
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
      'phone graph information scrolls with keyboard inset and closes without mutation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final document = crowdedCanvasFixture();
    final before = document.toJson();
    await tester
        .pumpWidget(MaterialApp(home: GraphCanvasScreen(document: document)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Graph Information'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Company'));
    await tester.enterText(field('Company'), 'Discard this edit');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save Changes'), 300,
        scrollable: find
            .descendant(
                of: find.byType(NewJobScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cancel edits'));
    await tester.pumpAndSettle();
    expect(document.toJson(), before);
  });
}
