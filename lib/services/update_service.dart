import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adiman/src/rust/api/utils.dart' as rust_utils;
import 'package:adiman/widgets/snackbar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:system_info2/system_info2.dart';

class AdimanUpdater {
  late final AppVersion _cvers;

  AdimanUpdater._internal({
    required AppVersion cvers,
  }) : _cvers = cvers;

  static AdimanUpdater? _instance;

  static Future<AdimanUpdater> initialize() async {
    if (_instance == null) {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final AppVersion version = AppVersion.parse(packageInfo.version);

      _instance = AdimanUpdater._internal(cvers: version);
    }
    return _instance!;
  }

  AppVersion get ver => _cvers;

  void checkUpdate(BuildContext context) async {
    final String? fetchedVersion = await rust_utils.getLatestVersion();
    if (fetchedVersion == null) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Failed to get latest version, check your internet or the terminal'));
      return;
    }
    final AppVersion v = AppVersion.parse(fetchedVersion);
    if (v.isNewerThan(ver)) {
      _update(context);
    }
  }

  void _update(BuildContext context) async {
    final String? here = Platform.environment['APPIMAGE'];
    if (here == null) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'APPIMAGE environment variable does not exist, cannot update non-appimage'));
      return;
    }
    if (!Platform.isLinux) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content: 'OS is not linux - no github releases available'));
      return;
    }
    final String arch = SysInfo.kernelArchitecture.name
        .toLowerCase(); // I don't know what this actually returns
    if (arch != "arm64" && arch != "x86_64") {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Architecture $arch is unsupported - no github releases available'));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(content: 'Updating executable'));
    final bool updateRes =
        await rust_utils.updateExecutable(arch: arch, expath: here);
    if (updateRes) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Successfully updated! You may restart the app for updates to apply'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content: 'Update failed, check the terminal for more info'));
    }
  }
}

class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
  }) : assert(major >= 0 && minor >= 0 && patch >= 0);

  factory AppVersion.parse(String versionString) {
    if (versionString.startsWith('v')) {
      versionString = versionString.substring(1);
    }
    final parts = versionString.split('.');
    if (parts.length != 3) {
      throw FormatException(
          'Invalid version string format: "$versionString". Expected format "X.Y.Z".');
    }

    try {
      final major = int.parse(parts[0]);
      final minor = int.parse(parts[1]);
      final patch = int.parse(parts[2]);

      return AppVersion(
        major: major,
        minor: minor,
        patch: patch,
      );
    } on FormatException catch (_) {
      throw FormatException(
          'Invalid version string format: "$versionString". Components must be integers.');
    }
  }

  @override
  String toString() {
    return '$major.$minor.$patch';
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  bool isOlderThan(AppVersion other) => compareTo(other) < 0;
  bool isSameVersion(AppVersion other) => compareTo(other) == 0;
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => major.hashCode ^ minor.hashCode ^ patch.hashCode;
}
