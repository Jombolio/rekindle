import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rekindle/core/update/semver.dart';
import 'package:rekindle/core/update/update_service.dart';

Map<String, dynamic> _release(String tag,
        {bool pre = false, bool draft = false}) =>
    {
      'tag_name': tag,
      'name': 'Rekindle $tag',
      'prerelease': pre,
      'draft': draft,
      'html_url': 'https://git.jombo.uk/Jombo/rekindle/releases/tag/$tag',
      'body': 'notes',
      'assets': [
        {
          'name': 'Rekindle-windows-x64Setup.exe',
          'browser_download_url': 'https://git.jombo.uk/dl/$tag/setup.exe',
          'size': 10,
        },
      ],
    };

/// Answers every request with [body] and records the URLs asked for.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);
  final Object body;
  final requested = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requested.add(options.uri);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SemVersion', () {
    test('parses tags, pre-releases and build metadata', () {
      expect(SemVersion.tryParse('v1.5.0-beta.1'),
          const SemVersion(1, 5, 0, 'beta.1'));
      expect(SemVersion.tryParse('1.5.0-beta.1+21'),
          const SemVersion(1, 5, 0, 'beta.1'));
      expect(SemVersion.tryParse('1.4.1'), const SemVersion(1, 4, 1));
    });

    test('rejects non-versions', () {
      for (final t in ['', 'Release', 'Pre-release', '1.5', '1.5.0-', '1.5.0-a..b']) {
        expect(SemVersion.tryParse(t), isNull, reason: t);
      }
    });

    test('orders per semver, pre-releases before their release', () {
      const ordered = [
        '1.4.1', '1.5.0-alpha', '1.5.0-alpha.1', '1.5.0-alpha.beta',
        '1.5.0-beta', '1.5.0-beta.2', '1.5.0-beta.11', '1.5.0-rc.1',
        '1.5.0', '1.5.1', '1.10.0', '2.0.0',
      ];
      for (var i = 1; i < ordered.length; i++) {
        final a = SemVersion.tryParse(ordered[i - 1])!;
        final b = SemVersion.tryParse(ordered[i])!;
        expect(a < b, isTrue, reason: '${ordered[i - 1]} < ${ordered[i]}');
      }
    });
  });

  group('UpdateService.selectNewest', () {
    List<ReleaseInfo> releases(List<Map<String, dynamic>> raw) =>
        raw.map(ReleaseInfo.fromJson).toList();

    final mixed = releases([
      _release('v1.4.0'),
      _release('v1.4.1'),
      _release('v1.5.0-beta.1', pre: true),
      _release('v9.0.0', draft: true),
      {'tag_name': 'Release', 'name': 'Release', 'assets': []},
    ]);

    test('stable skips pre-releases, drafts and unversioned tags', () {
      expect(UpdateService.selectNewest(mixed, includePreReleases: false)!.tagName,
          'v1.4.1');
    });

    test('pre-release channel picks the beta', () {
      expect(UpdateService.selectNewest(mixed, includePreReleases: true)!.tagName,
          'v1.5.0-beta.1');
    });

    test('stable ignores a beta tag not flagged as a pre-release', () {
      final list = releases([_release('v1.4.1'), _release('v1.5.0-beta.1')]);
      expect(UpdateService.selectNewest(list, includePreReleases: false)!.tagName,
          'v1.4.1');
    });

    test('a release outranks its own release candidates', () {
      final list =
          releases([_release('v1.5.0-rc.1', pre: true), _release('v1.5.0')]);
      expect(UpdateService.selectNewest(list, includePreReleases: true)!.tagName,
          'v1.5.0');
    });
  });

  group('UpdateService.isNewer', () {
    test('never downgrades a pre-release user to an older stable', () {
      expect(UpdateService.isNewer('1.4.1', '1.5.0-beta.1'), isFalse);
    });

    test('the release is newer than its beta', () {
      expect(UpdateService.isNewer('1.5.0', '1.5.0-beta.1'), isTrue);
    });

    test('an unparseable current version accepts any release', () {
      expect(UpdateService.isNewer('1.0.0', 'unknown'), isTrue);
    });
  });

  test('ReleaseInfo falls back to the version in the release name', () {
    final r = ReleaseInfo.fromJson(
        {'tag_name': 'Pre-release', 'name': 'Rekindle v1.5.0-beta.2', 'assets': []});
    expect(r.version, '1.5.0-beta.2');
  });

  group('UpdateService.check', () {
    final gitea = [_release('v1.4.1'), _release('v1.5.0-beta.1', pre: true)];

    UpdateService service(_FakeAdapter adapter) =>
        UpdateService(dio: Dio()..httpClientAdapter = adapter);

    test('asks Gitea, and stable users stay on stable', () async {
      PackageInfo.setMockInitialValues(
          appName: 'rekindle', packageName: 'rekindle', version: '1.4.1',
          buildNumber: '20', buildSignature: '');
      final adapter = _FakeAdapter(gitea);

      final result = await service(adapter).check();

      expect(adapter.requested.single.host, 'git.jombo.uk');
      expect(adapter.requested.single.path,
          '/api/v1/repos/Jombo/rekindle/releases');
      expect(result.status, UpdateStatus.upToDate);
    });

    test('pre-release users are offered the beta', () async {
      PackageInfo.setMockInitialValues(
          appName: 'rekindle', packageName: 'rekindle', version: '1.4.1',
          buildNumber: '20', buildSignature: '');

      final result =
          await service(_FakeAdapter(gitea)).check(includePreReleases: true);

      expect(result.status, UpdateStatus.updateAvailable);
      expect(result.release!.version, '1.5.0-beta.1');
    });

    test('a source with nothing eligible is an answer: up to date', () async {
      // Gitea has only a beta; a stable-channel user is simply up to date.
      PackageInfo.setMockInitialValues(
          appName: 'rekindle', packageName: 'rekindle', version: '1.5.0-beta.1',
          buildNumber: '21', buildSignature: '');
      final adapter =
          _FakeAdapter([_release('v1.5.0-beta.1', pre: true)]);

      final result = await service(adapter).check();

      expect(result.status, UpdateStatus.upToDate);
      expect(result.release, isNull);
      expect(adapter.requested, hasLength(1), reason: 'no fallback to GitHub');
    });
  });

  group('GitHub fallback', () {
    setUp(() => PackageInfo.setMockInitialValues(
        appName: 'rekindle', packageName: 'rekindle', version: '1.5.0-beta.1',
        buildNumber: '21', buildSignature: ''));

    final github = [_release('v1.5.0')];

    UpdateService service(_HostAdapter adapter) =>
        UpdateService(dio: Dio()..httpClientAdapter = adapter);

    test('Gitea answering means GitHub is never asked', () async {
      final adapter = _HostAdapter(
          gitea: [_release('v1.5.0-beta.2', pre: true)], github: github);

      final result = await service(adapter).check(includePreReleases: true);

      expect(result.source, 'Gitea');
      expect(result.usedFallback, isFalse);
      expect(result.release!.version, '1.5.0-beta.2');
      expect(adapter.hosts, isNot(contains('api.github.com')));
    });

    for (final (label, gitea) in [
      ('unreachable', _Fail.connection),
      ('HTTP 503', _Fail.http503),
      ('not JSON', _Fail.junk),
    ]) {
      test('Gitea $label: falls back to GitHub', () async {
        final adapter = _HostAdapter(gitea: gitea, github: github);

        final result = await service(adapter).check();

        expect(result.source, 'GitHub');
        expect(result.usedFallback, isTrue);
        expect(result.status, UpdateStatus.updateAvailable);
        expect(result.release!.version, '1.5.0');
      });
    }

    test('both unreachable: one error naming each source', () async {
      final adapter =
          _HostAdapter(gitea: _Fail.connection, github: _Fail.http503);

      final result = await service(adapter).check();

      expect(result.status, UpdateStatus.error);
      expect(result.error, contains('Gitea: unreachable'));
      expect(result.error, contains('GitHub: HTTP 503'));
    });
  });
}

enum _Fail { connection, http503, junk }

/// Answers per host: a release list (any JSON) or a failure.
class _HostAdapter implements HttpClientAdapter {
  _HostAdapter({required this.gitea, required this.github});
  final Object gitea;
  final Object github;
  final hosts = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    hosts.add(options.uri.host);
    final answer = options.uri.host == 'api.github.com' ? github : gitea;
    return switch (answer) {
      _Fail.connection => throw DioException.connectionError(
          requestOptions: options, reason: 'refused'),
      _Fail.http503 => ResponseBody.fromString('down', 503),
      _Fail.junk => ResponseBody.fromString('<html>maintenance</html>', 200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          }),
      _ => ResponseBody.fromString(jsonEncode(answer), 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        }),
    };
  }

  @override
  void close({bool force = false}) {}
}
