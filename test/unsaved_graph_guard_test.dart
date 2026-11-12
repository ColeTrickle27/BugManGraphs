import 'dart:async';
import 'package:bugman_graphs/widgets/unsaved_graph_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final choice in ['Stay', 'Discard and continue', 'Save and continue']) {
    testWidgets('dirty back: $choice', (t) async {
      bool dirty = true;
      int saves = 0;
      await t.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => UnsavedGraphGuard(
                                  enabled: true,
                                  hasChanges: () => dirty,
                                  isSaving: () => false,
                                  beforeExit: () {},
                                  save: () async {
                                    saves++;
                                    dirty = false;
                                    return true;
                                  },
                                  child: Scaffold(
                                      appBar: AppBar(
                                          title: const Text('Editor')))))),
                      child: const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await t.tap(find.text(choice));
      await t.pumpAndSettle();
      expect(find.text('Editor'),
          choice == 'Stay' ? findsOneWidget : findsNothing);
      expect(saves, choice == 'Save and continue' ? 1 : 0);
    });
  }
  for (final outcome in ['failure', 'pending', 'concurrent edit', 'clean']) {
    testWidgets('exit preserves changes during $outcome', (t) async {
      bool dirty = outcome != 'clean';
      int saves = 0;
      final pending = Completer<bool>();
      await t.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => UnsavedGraphGuard(
                                  enabled: true,
                                  hasChanges: () => dirty,
                                  isSaving: () => false,
                                  beforeExit: () {},
                                  save: () async {
                                    saves++;
                                    if (outcome == 'pending') {
                                      return pending.future;
                                    }
                                    if (outcome == 'failure') return false;
                                    return true;
                                  },
                                  child: Scaffold(
                                      appBar: AppBar(
                                          title: const Text('Editor')))))),
                      child: const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      if (outcome == 'clean') {
        expect(find.text('Editor'), findsNothing);
        expect(saves, 0);
        return;
      }
      await t.tap(find.text('Save and continue'));
      await t.pumpAndSettle();
      expect(find.text('Editor'), findsOneWidget);
      if (outcome == 'pending') {
        await t.binding.handlePopRoute();
        await t.pump();
        expect(saves, 1);
        dirty = false;
        pending.complete(true);
        await t.pumpAndSettle();
        expect(find.text('Editor'), findsNothing);
      } else {
        expect(dirty, true);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
      }
    });
  }
  for (final mode in [
    'already saving',
    'disabled',
    'inline edit',
    'exception',
    'repeated back'
  ]) {
    testWidgets('guard boundary $mode', (t) async {
      bool dirty = mode != 'inline edit';
      int saves = 0;
      await t.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => UnsavedGraphGuard(
                                  enabled: mode != 'disabled',
                                  hasChanges: () => dirty,
                                  isSaving: () => mode == 'already saving',
                                  beforeExit: () {
                                    dirty = true;
                                  },
                                  save: () async {
                                    saves++;
                                    throw StateError('Synthetic failure');
                                  },
                                  child: Scaffold(
                                      appBar: AppBar(
                                          title: const Text('Editor')))))),
                      child: const Text('Open'))))));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      if (mode == 'disabled') {
        expect(find.text('Editor'), findsNothing);
        return;
      }
      if (mode == 'already saving') {
        expect(find.text('Unsaved changes'), findsNothing);
        expect(find.text('Editor'), findsOneWidget);
        return;
      }
      expect(find.text('Unsaved changes'), findsOneWidget);
      if (mode == 'exception') {
        await t.tap(find.text('Save and continue'));
        await t.pumpAndSettle();
        expect(find.text('Editor'), findsOneWidget);
        expect(saves, 1);
      }
      if (mode == 'repeated back') {
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Editor'), findsOneWidget);
        expect(saves, 0);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Unsaved changes'), findsOneWidget);
      }
    });
  }
}
