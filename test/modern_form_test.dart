import 'printing_test_support.dart';
import 'package:bugman_graphs/models/job.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bugman_graphs/widgets/moisture_reading_dialog.dart';
import 'package:bugman_graphs/screens/new_job_screen.dart';
import 'package:bugman_graphs/services/ops_user_service.dart';
import 'package:bugman_graphs/theme/app_theme.dart';

void main() {
  for (final size in [const Size(1400, 900), const Size(390, 844)]) {
    testWidgets('moisture selects default, replaces, cancels and resets $size',
        (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      String? result;
      await t.pumpWidget(MaterialApp(
          theme: buildBugManTheme(),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<String>(
                            context: context,
                            builder: (_) => const MoistureReadingDialog());
                      },
                      child: const Text('Place'))))));
      for (var i = 0; i < 2; i++) {
        await t.tap(find.text('Place'));
        await t.pumpAndSettle();
        final field = t.widget<TextField>(
            find.byKey(const ValueKey('moisture-reading-entry')));
        expect(field.controller!.text, '15');
        expect(field.controller!.selection,
            const TextSelection(baseOffset: 0, extentOffset: 2));
        expect(field.focusNode!.hasFocus, isTrue);
        expect(field.keyboardType,
            const TextInputType.numberWithOptions(decimal: true));
        final old = field.controller!.value;
        final selection = old.selection;
        t.testTextInput.updateEditingValue(TextEditingValue(
            text: old.text.replaceRange(selection.start, selection.end, '22.5'),
            selection: const TextSelection.collapsed(offset: 4)));
        await t.pump();
        expect(field.controller!.text, '22.5');
        await t.tap(find.text(i == 0 ? 'Save' : 'Cancel'));
        await t.pumpAndSettle();
        expect(result, i == 0 ? '22.5' : null);
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'responsive form has button selections and transactional contact popup',
      (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1400, 1000);
    addTearDown(t.view.reset);
    Job? saved;
    await t.pumpWidget(MaterialApp(
        theme: buildBugManTheme(),
        home: NewJobScreen(
            opsUserService: UnavailableOpsUserService(), onCreateJob: (job) { saved=job; })));
    await t.pumpAndSettle();
    await t.tap(find.text('New Customer'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Inspection'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Commercial'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Commercial'))
            .selected,
        isTrue);
    await t.tap(find.byKey(const ValueKey('optional-contact-button')));
    await t.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Name');
    await t.enterText(name, 'Contact draft');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Contact draft'), findsNothing);
    await t.tap(find.byKey(const ValueKey('optional-contact-button')));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Contact saved');
    await t.tap(find.text('Save Contact'));
    await t.pumpAndSettle();
    expect(find.text('Contact saved'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('created-by-manual')), 'Manual entry');
    await t.tap(find.widgetWithText(ChoiceChip,'WDIR'));
    await t.tap(find.text('Create Graph'));
    await t.pumpAndSettle();
    expect(saved!.createdBy,'Manual entry');
    expect(saved!.serviceType,'WDIR');
    expect(saved!.intakeDetails['customerType'],'Commercial');
    expect(saved!.intakeDetails['contactName'],'Contact saved');
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
