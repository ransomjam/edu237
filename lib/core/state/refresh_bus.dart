import 'package:flutter/widgets.dart';

/// A tiny app-wide signal used to keep relationship-backed lists fresh across
/// the shell's kept-alive tabs.
///
/// When a teacher accepts a request on the Requests tab, the My Students tab is
/// already built (the shell keeps branches alive) and would otherwise show a
/// stale list. Accepting pings [relationshipsChanged]; screens that show
/// connected students listen and reload. This makes refresh reliable rather
/// than depending on accidental widget rebuilds.
class RefreshBus extends ChangeNotifier {
  void relationshipsChanged() => notifyListeners();
  void profileChanged() => notifyListeners();
}

/// Makes a [RefreshBus] available to the widget tree.
class RefreshBusScope extends InheritedNotifier<RefreshBus> {
  const RefreshBusScope({
    super.key,
    required RefreshBus bus,
    required super.child,
  }) : super(notifier: bus);

  /// Returns the bus, or null when there is no scope (e.g. focused widget
  /// tests that pump a screen directly). Callers must tolerate null.
  static RefreshBus? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<RefreshBusScope>()
        ?.notifier;
  }
}
