/// Conformance group: policy. Contract section 5.
library;

import 'package:localaze/localaze.dart';
import 'package:test/test.dart';

bool accepts(String held, String offered, LocalazeUpdatePolicy policy) =>
    LocalazeVersion.accepts(held, offered, policy);

void main() {
  const patchOnly = LocalazeUpdatePolicy.patchOnly;
  const minorAndPatch = LocalazeUpdatePolicy.minorAndPatch;
  const none = LocalazeUpdatePolicy.none;
  const range = LocalazeUpdatePolicy.range(from: '1.0.0', to: '1.2.0');

  test('policy.patch-accepted', () {
    expect(accepts('1.0.0', '1.0.1', minorAndPatch), isTrue);
  });

  test('policy.patch-accepted-under-patch-only', () {
    expect(accepts('1.0.0', '1.0.1', patchOnly), isTrue);
  });

  test('policy.minor-accepted', () {
    expect(accepts('1.0.0', '1.1.0', minorAndPatch), isTrue);
  });

  test('policy.minor-refused-under-patch-only', () {
    expect(accepts('1.0.0', '1.1.0', patchOnly), isFalse);
  });

  group('policy.major-refused-always', () {
    // The one rule no policy may override. LZ-62 defines major as
    // signature-breaking by construction, so its messages no longer take the
    // parameters generated call sites pass.
    for (final policy in [none, patchOnly, minorAndPatch, range]) {
      test('under ${policy.name}', () {
        expect(accepts('1.0.0', '2.0.0', policy), isFalse);
      });
    }

    test('even a major that is otherwise inside an explicit range', () {
      const wide = LocalazeUpdatePolicy.range(from: '1.0.0', to: '9.9.9');
      expect(accepts('1.0.0', '2.0.0', wide), isFalse);
    });
  });

  test('policy.none-fetches-nothing', () {
    // Not merely a refused result: no request is made at all. The updater reads
    // this flag before touching the transport.
    expect(none.fetches, isFalse);
    expect(minorAndPatch.fetches, isTrue);
  });

  test('policy.downgrade-refused', () {
    expect(accepts('1.1.0', '1.0.1', minorAndPatch), isFalse);
  });

  test('policy.same-version-is-up-to-date', () {
    // accepts() still says no — there is nothing to take. The updater turns
    // that into upToDate rather than refusedByPolicy, which fetch_test covers.
    expect(accepts('1.0.0', '1.0.0', minorAndPatch), isFalse);
  });

  test('policy.numeric-comparison', () {
    // String comparison would put 1.10.0 below 1.9.0, a bug that only shows up
    // once a project has shipped ten minor releases.
    expect(accepts('1.9.0', '1.10.0', minorAndPatch), isTrue);
    expect(accepts('1.10.0', '1.9.0', minorAndPatch), isFalse);
    expect(LocalazeVersion.parse('1.10.0')!
        .compareTo(LocalazeVersion.parse('1.9.0')!), greaterThan(0));
  });

  group('policy.malformed-version-refused', () {
    for (final bad in ['latest', '2.0', '', '1.0.0-rc1', 'x.y.z', '1.-1.0']) {
      test('"$bad"', () {
        expect(LocalazeVersion.parse(bad), isNull);
        expect(accepts('1.0.0', bad, minorAndPatch), isFalse);
        expect(accepts(bad, '1.0.1', minorAndPatch), isFalse);
      });
    }
  });

  group('range', () {
    test('accepts inside the bounds', () {
      expect(accepts('1.0.0', '1.1.0', range), isTrue);
      expect(accepts('1.0.0', '1.2.0', range), isTrue);
    });

    test('refuses above the upper bound', () {
      expect(accepts('1.0.0', '1.3.0', range), isFalse);
    });

    test('refuses a malformed bound rather than guessing', () {
      const broken = LocalazeUpdatePolicy.range(from: '1.0', to: 'latest');
      expect(accepts('1.0.0', '1.1.0', broken), isFalse);
    });
  });
}
