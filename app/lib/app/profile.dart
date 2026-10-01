import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Local player identity (persisted). `pid` lets the host reattach us after
/// a reconnect and feeds the random-chicken history.
class Profile {
  final String pid;
  final String name;
  final int gamesPlayed;

  const Profile({
    required this.pid,
    required this.name,
    required this.gamesPlayed,
  });

  Profile copyWith({String? name, int? gamesPlayed}) => Profile(
    pid: pid,
    name: name ?? this.name,
    gamesPlayed: gamesPlayed ?? this.gamesPlayed,
  );
}

class ProfileStore {
  static const _kPid = 'pid', _kName = 'name', _kGames = 'games';

  static Future<Profile> load() async {
    final prefs = await SharedPreferences.getInstance();
    var pid = prefs.getString(_kPid);
    if (pid == null || pid.isEmpty) {
      final r = Random.secure();
      pid = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_kPid, pid);
    }
    return Profile(
      pid: pid,
      name: prefs.getString(_kName) ?? '',
      gamesPlayed: prefs.getInt(_kGames) ?? 0,
    );
  }

  static Future<void> save(Profile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, p.name);
    await prefs.setInt(_kGames, p.gamesPlayed);
  }
}
