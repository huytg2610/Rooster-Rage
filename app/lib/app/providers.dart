import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/client_link.dart';
import '../net/session.dart';
import 'profile.dart';

final profileProvider = FutureProvider<Profile>((ref) => ProfileStore.load());

/// The active room session (null on the home screen).
class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  Session startLocal(Profile p) => _set(
    Session(
      link: LocalLink(),
      profile: p,
      isLocal: true,
      onProfileChanged: _persist,
    ),
  );

  Session join(Profile p, Uri uri) {
    late Session s;
    s = Session(
      link: WsLink(uri, onReconnect: () => s.hello()),
      profile: p,
      isLocal: false,
      onProfileChanged: _persist,
    );
    return _set(s);
  }

  Session _set(Session s) {
    state?.dispose();
    state = s;
    return s;
  }

  void leave() {
    state?.dispose();
    state = null;
  }

  void _persist(Profile p) {
    ProfileStore.save(p);
    ref.invalidate(profileProvider);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);
