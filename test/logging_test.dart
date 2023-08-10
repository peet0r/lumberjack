// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final hierarchicalLoggingEnabledDefault = hierarchicalLoggingEnabled;

  test('level comparison is a valid comparator', () {
    const level1 = Level('NOT_REAL1', 253);
    expect(level1 == level1, isTrue);
    expect(level1 <= level1, isTrue);
    expect(level1 >= level1, isTrue);
    expect(level1 < level1, isFalse);
    expect(level1 > level1, isFalse);

    const level2 = Level('NOT_REAL2', 455);
    expect(level1 <= level2, isTrue);
    expect(level1 < level2, isTrue);
    expect(level2 >= level1, isTrue);
    expect(level2 > level1, isTrue);

    const level3 = Level('NOT_REAL3', 253);
    expect(level1, isNot(same(level3))); // different instances
    expect(level1, equals(level3)); // same value.
  });

  test('default levels are in order', () {
    const levels = Level.LEVELS;

    for (var i = 0; i < levels.length; i++) {
      for (var j = i + 1; j < levels.length; j++) {
        expect(levels[i] < levels[j], isTrue);
      }
    }
  });

  test('levels are comparable', () {
    final unsorted = [
      Level.INFO,
      Level.DEBUG,
      Level.ERROR,
      Level.OFF,
      Level.ALL,
      Level.WARN,
      Level.VERBOSE,
    ];

    const sorted = Level.LEVELS;

    expect(unsorted, isNot(orderedEquals(sorted)));

    unsorted.sort();
    expect(unsorted, orderedEquals(sorted));
  });

  test('levels are hashable', () {
    final map = <Level, String>{};
    map[Level.INFO] = 'info';
    map[Level.ERROR] = 'error';
    expect(map[Level.INFO], same('info'));
    expect(map[Level.ERROR], same('error'));
  });

  test('logger name cannot start with a "." ', () {
    expect(() => Logger('.c'), throwsArgumentError);
  });

  test('logger name cannot end with a "."', () {
    expect(() => Logger('a.'), throwsArgumentError);
    expect(() => Logger('a..d'), throwsArgumentError);
  });

  test('root level has proper defaults', () {
    expect(Logger.root, isNotNull);
    expect(Logger.root.parent, null);
    expect(Logger.root.level, defaultLevel);
  });

  test('logger naming is hierarchical', () {
    final c = Logger('a.b.c');
    expect(c.name, equals('c'));
    expect(c.parent!.name, equals('b'));
    expect(c.parent!.parent!.name, equals('a'));
    expect(c.parent!.parent!.parent!.name, equals(''));
    expect(c.parent!.parent!.parent!.parent, isNull);
  });

  test('logger full name', () {
    final c = Logger('a.b.c');
    expect(c.fullName, equals('a.b.c'));
    expect(c.parent!.fullName, equals('a.b'));
    expect(c.parent!.parent!.fullName, equals('a'));
    expect(c.parent!.parent!.parent!.fullName, equals(''));
    expect(c.parent!.parent!.parent!.parent, isNull);
  });

  test('logger parent-child links are correct', () {
    final a = Logger('a');
    final b = Logger('a.b');
    final c = Logger('a.c');
    expect(a, same(b.parent));
    expect(a, same(c.parent));
    expect(a.children['b'], same(b));
    expect(a.children['c'], same(c));
  });

  test('loggers are singletons', () {
    final a1 = Logger('a');
    final a2 = Logger('a');
    final b = Logger('a.b');
    final root = Logger.root;
    expect(a1, same(a2));
    expect(a1, same(b.parent));
    expect(root, same(a1.parent));
    expect(root, same(Logger('')));
  });

  test('cannot directly manipulate Logger.children', () {
    final loggerAB = Logger('a.b');
    final loggerA = loggerAB.parent!;

    expect(loggerA.children['b'], same(loggerAB), reason: 'can read Children');

    expect(() {
      loggerAB.children['test'] = Logger('Fake1234');
    }, throwsUnsupportedError, reason: 'Children is read-only');
  });

  test('stackTrace gets throw to LogRecord', () {
    Logger.root.level = Level.INFO;

    final records = <LogRecord>[];

    final sub = Logger.root.onRecord.listen(records.add);

    try {
      throw UnsupportedError('test exception');
    } catch (error, stack) {
      Logger.root.log(Level.ERROR, 'error', error, stack);
      Logger.root.warn('warn', error, stack);
    }

    Logger.root.log(Level.ERROR, 'error');

    sub.cancel();

    expect(records, hasLength(3));

    final severe = records[0];
    expect(severe.message, 'error');
    expect(severe.error is UnsupportedError, isTrue);
    expect(severe.stackTrace is StackTrace, isTrue);

    final warning = records[1];
    expect(warning.message, 'warn');
    expect(warning.error is UnsupportedError, isTrue);
    expect(warning.stackTrace is StackTrace, isTrue);

    final shout = records[2];
    expect(shout.message, 'error');
    expect(shout.error, isNull);
    expect(shout.stackTrace, isNull);
  });

  group('zone gets recorded to LogRecord', () {
    test('root zone', () {
      final root = Logger.root;

      final recordingZone = Zone.current;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);
      root.info('hello');

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });

    test('child zone', () {
      final root = Logger.root;

      late Zone recordingZone;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);

      runZoned(() {
        recordingZone = Zone.current;
        root.info('hello');
      });

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });

    test('custom zone', () {
      final root = Logger.root;

      late Zone recordingZone;
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);

      runZoned(() {
        recordingZone = Zone.current;
      });

      runZoned(() => root.log(Level.INFO, 'hello', null, null, recordingZone));

      expect(records, hasLength(1));
      expect(records.first.zone, equals(recordingZone));
    });
  });

  group('detached loggers', () {
    tearDown(() {
      hierarchicalLoggingEnabled = hierarchicalLoggingEnabledDefault;
      Logger.root.level = defaultLevel;
    });

    test('create new instances of Logger', () {
      final a1 = Logger.detached('a');
      final a2 = Logger.detached('a');
      final a = Logger('a');

      expect(a1, isNot(a2));
      expect(a1, isNot(a));
      expect(a2, isNot(a));
    });

    test('parent is null', () {
      final a = Logger.detached('a');
      expect(a.parent, null);
    });

    test('children is empty', () {
      final a = Logger.detached('a');
      expect(a.children, {});
    });

    test('have levels independent of the root level', () {
      void testDetachedLoggerLevel(bool withHierarchy) {
        hierarchicalLoggingEnabled = withHierarchy;

        const newRootLevel = Level.ALL;
        const newDetachedLevel = Level.OFF;

        Logger.root.level = newRootLevel;

        final detached = Logger.detached('a');
        expect(detached.level, defaultLevel);
        expect(Logger.root.level, newRootLevel);

        detached.level = newDetachedLevel;
        expect(detached.level, newDetachedLevel);
        expect(Logger.root.level, newRootLevel);
      }

      testDetachedLoggerLevel(false);
      testDetachedLoggerLevel(true);
    });

    test('log messages regardless of hierarchy', () {
      void testDetachedLoggerOnRecord(bool withHierarchy) {
        var calls = 0;
        void handler(_) => calls += 1;

        hierarchicalLoggingEnabled = withHierarchy;

        final detached = Logger.detached('a');
        detached.level = Level.ALL;
        detached.onRecord.listen(handler);

        Logger.root.info('foo');
        expect(calls, 0);

        detached.info('foo');
        detached.info('foo');
        expect(calls, 2);
      }

      testDetachedLoggerOnRecord(false);
      testDetachedLoggerOnRecord(true);
    });
  });

  group('mutating levels', () {
    final root = Logger.root;
    final a = Logger('a');
    final b = Logger('a.b');
    final c = Logger('a.b.c');
    final d = Logger('a.b.c.d');
    final e = Logger('a.b.c.d.e');

    setUp(() {
      hierarchicalLoggingEnabled = true;
      root.level = Level.INFO;
      a.level = null;
      b.level = null;
      c.level = null;
      d.level = null;
      e.level = null;
      root.clearListeners();
      a.clearListeners();
      b.clearListeners();
      c.clearListeners();
      d.clearListeners();
      e.clearListeners();
      hierarchicalLoggingEnabled = false;
      root.level = Level.INFO;
    });

    test('cannot set level if hierarchy is disabled', () {
      expect(() => a.level = Level.DEBUG, throwsUnsupportedError);
    });

    test('cannot set the level to null on the root logger', () {
      expect(() => root.level = null, throwsUnsupportedError);
    });

    test('cannot set the level to null on a detached logger', () {
      expect(() => Logger.detached('l').level = null, throwsUnsupportedError);
    });

    test('loggers effective level - no hierarchy', () {
      expect(root.level, equals(Level.INFO));
      expect(a.level, equals(Level.INFO));
      expect(b.level, equals(Level.INFO));

      root.level = Level.ERROR;

      expect(root.level, equals(Level.ERROR));
      expect(a.level, equals(Level.ERROR));
      expect(b.level, equals(Level.ERROR));
    });

    test('loggers effective level - with hierarchy', () {
      hierarchicalLoggingEnabled = true;
      expect(root.level, equals(Level.INFO));
      expect(a.level, equals(Level.INFO));
      expect(b.level, equals(Level.INFO));
      expect(c.level, equals(Level.INFO));

      root.level = Level.ERROR;
      b.level = Level.DEBUG;

      expect(root.level, equals(Level.ERROR));
      expect(a.level, equals(Level.ERROR));
      expect(b.level, equals(Level.DEBUG));
      expect(c.level, equals(Level.DEBUG));
    });

    test('loggers effective level - with changing hierarchy', () {
      hierarchicalLoggingEnabled = true;
      d.level = Level.ERROR;
      hierarchicalLoggingEnabled = false;

      expect(root.level, Level.INFO);
      expect(d.level, root.level);
      expect(e.level, root.level);
    });

    test('isLoggable is appropriate', () {
      hierarchicalLoggingEnabled = true;
      root.level = Level.ERROR;
      c.level = Level.ALL;
      e.level = Level.OFF;

      expect(root.isLoggable(Level.ERROR), isTrue);
      expect(root.isLoggable(Level.ERROR), isTrue);
      expect(root.isLoggable(Level.WARN), isFalse);
      expect(c.isLoggable(Level.VERBOSE), isTrue);
      expect(c.isLoggable(Level.DEBUG), isTrue);
      expect(e.isLoggable(Level.ERROR), isFalse);
    });

    test('add/remove handlers - no hierarchy', () {
      var calls = 0;
      void handler(_) {
        calls++;
      }

      final sub = c.onRecord.listen(handler);
      root.info('foo');
      root.info('foo');
      expect(calls, equals(2));
      sub.cancel();
      root.info('foo');
      expect(calls, equals(2));
    });

    test('add/remove handlers - with hierarchy', () {
      hierarchicalLoggingEnabled = true;
      var calls = 0;
      void handler(_) {
        calls++;
      }

      c.onRecord.listen(handler);
      root.info('foo');
      root.info('foo');
      expect(calls, equals(0));
    });

    test('logging methods store appropriate level', () {
      root.level = Level.ALL;
      final rootMessages = [];
      root.onRecord.listen((record) {
        rootMessages.add('${record.level}: ${record.message}');
      });

      root.verbose('1');
      root.debug('2');
      root.info('3');
      root.warn('4');
      root.error('5');

      expect(
          rootMessages,
          equals([
            'VERBOSE: 1',
            'DEBUG: 2',
            'INFO: 3',
            'WARN: 4',
            'ERROR: 5',
          ]));
    });

    test('logging methods store exception', () {
      root.level = Level.ALL;
      final rootMessages = [];
      root.onRecord.listen((r) {
        rootMessages.add('${r.level}: ${r.message} ${r.error}');
      });

      root.verbose('1');
      root.verbose('2');
      root.debug('3');
      root.debug('4');
      root.info('5');
      root.warn('6');
      root.error('7');
      root.error('8');
      root.verbose('1', 'a');
      root.verbose('2', 'b');
      root.debug('3', ['c']);
      root.debug('4', 'd');
      root.info('5', 'e');
      root.warn('6', 'f');
      root.error('7', 'g');
      root.error('8', 'h');

      expect(
          rootMessages,
          equals([
            'VERBOSE: 1 null',
            'VERBOSE: 2 null',
            'DEBUG: 3 null',
            'DEBUG: 4 null',
            'INFO: 5 null',
            'WARN: 6 null',
            'ERROR: 7 null',
            'ERROR: 8 null',
            'VERBOSE: 1 a',
            'VERBOSE: 2 b',
            'DEBUG: 3 [c]',
            'DEBUG: 4 d',
            'INFO: 5 e',
            'WARN: 6 f',
            'ERROR: 7 g',
            'ERROR: 8 h'
          ]));
    });

    test('message logging - no hierarchy', () {
      root.level = Level.WARN;
      final rootMessages = [];
      final aMessages = [];
      final cMessages = [];
      c.onRecord.listen((record) {
        cMessages.add('${record.level}: ${record.message}');
      });
      a.onRecord.listen((record) {
        aMessages.add('${record.level}: ${record.message}');
      });
      root.onRecord.listen((record) {
        rootMessages.add('${record.level}: ${record.message}');
      });

      root.info('1');
      root.debug('2');
      root.error('3');

      b.info('4');
      b.error('5');
      b.warn('6');
      b.debug('7');

      c.debug('8');
      c.warn('9');
      c.error('10');

      expect(
          rootMessages,
          equals([
            // 'INFO: 1' is not loggable
            // 'DEBUG: 2' is not loggable
            'ERROR: 3',
            // 'INFO: 4' is not loggable
            'ERROR: 5',
            'WARN: 6',
            // 'DEBUG: 7' is not loggable
            // 'DEBUG: 8' is not loggable
            'WARN: 9',
            'ERROR: 10'
          ]));

      // no hierarchy means we all hear the same thing.
      expect(aMessages, equals(rootMessages));
      expect(cMessages, equals(rootMessages));
    });

    test('message logging - with hierarchy', () {
      hierarchicalLoggingEnabled = true;

      b.level = Level.WARN;

      final rootMessages = [];
      final aMessages = [];
      final cMessages = [];
      c.onRecord.listen((record) {
        cMessages.add('${record.level}: ${record.message}');
      });
      a.onRecord.listen((record) {
        aMessages.add('${record.level}: ${record.message}');
      });
      root.onRecord.listen((record) {
        rootMessages.add('${record.level}: ${record.message}');
      });

      root.info('1');
      root.debug('2');
      root.error('3');

      b.info('4');
      b.error('5');
      b.warn('6');
      b.debug('7');

      c.debug('8');
      c.warn('9');
      c.error('10');

      expect(
          rootMessages,
          equals([
            'INFO: 1',
            // 'DEBUG: 2' is not loggable
            'ERROR: 3',
            // 'INFO: 4' is not loggable
            'ERROR: 5',
            'WARN: 6',
            // 'DEBUG: 7' is not loggable
            // 'DEBUG: 8' is not loggable
            'WARN: 9',
            'ERROR: 10'
          ]));

      expect(
          aMessages,
          equals([
            // 1,2 and 3 are lower in the hierarchy
            // 'INFO: 4' is not loggable
            'ERROR: 5',
            'WARN: 6',
            // 'DEBUG: 7' is not loggable
            // 'DEBUG: 8' is not loggable
            'WARN: 9',
            'ERROR: 10'
          ]));

      expect(
          cMessages,
          equals([
            // 1 - 7 are lower in the hierarchy
            // 'DEBUG: 8' is not loggable
            'WARN: 9',
            'ERROR: 10'
          ]));
    });

    test('message logging - lazy functions', () {
      root.level = Level.INFO;
      final messages = [];
      root.onRecord.listen((record) {
        messages.add('${record.level}: ${record.message}');
      });

      var callCount = 0;
      String myClosure() => '${++callCount}';

      root.info(myClosure);
      root.verbose(myClosure); // Should not get evaluated.
      root.warn(myClosure);

      expect(
          messages,
          equals([
            'INFO: 1',
            'WARN: 2',
          ]));
    });

    test('message logging - calls toString', () {
      root.level = Level.INFO;
      final messages = [];
      final objects = [];
      final object = Object();
      root.onRecord.listen((record) {
        messages.add('${record.level}: ${record.message}');
        objects.add(record.object);
      });

      root.info(5);
      root.info(false);
      root.info([1, 2, 3]);
      root.info(() => 10);
      root.info(object);

      expect(
          messages,
          equals([
            'INFO: 5',
            'INFO: false',
            'INFO: [1, 2, 3]',
            'INFO: 10',
            "INFO: Instance of 'Object'"
          ]));

      expect(objects, [
        5,
        false,
        [1, 2, 3],
        10,
        object
      ]);
    });
  });

  group('recordStackTraceAtLevel', () {
    final root = Logger.root;
    tearDown(() {
      recordStackTraceAtLevel = Level.OFF;
      root.clearListeners();
    });

    test('no stack trace by default', () {
      final records = <LogRecord>[];
      root.onRecord.listen(records.add);
      root.error('hello');
      root.warn('hello');
      root.info('hello');
      expect(records, hasLength(3));
      expect(records[0].stackTrace, isNull);
      expect(records[1].stackTrace, isNull);
      expect(records[2].stackTrace, isNull);
    });

    test('trace recorded only on requested levels', () {
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.WARN;
      root.onRecord.listen(records.add);
      root.error('hello');
      root.warn('hello');
      root.info('hello');
      expect(records, hasLength(3));
      expect(records[0].stackTrace, isNotNull);
      expect(records[1].stackTrace, isNotNull);
      expect(records[2].stackTrace, isNull);
    });

    test('provided trace is used if given', () {
      final trace = StackTrace.current;
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.WARN;
      root.onRecord.listen(records.add);
      root.error('hello');
      root.warn('hello', 'a', trace);
      expect(records, hasLength(2));
      expect(records[0].stackTrace, isNot(equals(trace)));
      expect(records[1].stackTrace, trace);
    });

    test('error also generated when generating a trace', () {
      final records = <LogRecord>[];
      recordStackTraceAtLevel = Level.WARN;
      root.onRecord.listen(records.add);
      root.error('hello');
      root.warn('hello');
      root.info('hello');
      expect(records, hasLength(3));
      expect(records[0].error, isNotNull);
      expect(records[1].error, isNotNull);
      expect(records[2].error, isNull);
    });

    test('listen for level changed', () {
      final levels = <Level?>[];
      root.level = Level.ALL;
      root.onLevelChanged.listen(levels.add);
      root.level = Level.ERROR;
      root.level = Level.WARN;
      expect(levels, hasLength(2));
    });

    test('onLevelChanged is not emited if set the level to the same value', () {
      final levels = <Level?>[];
      root.level = Level.ALL;
      root.onLevelChanged.listen(levels.add);
      root.level = Level.ALL;
      expect(levels, hasLength(0));
    });

    test('setting level in a loop throws state error', () {
      root.level = Level.ALL;
      root.onLevelChanged.listen((event) {
        // Cannot fire new event. Controller is already firing an event
        expect(() => root.level = Level.ERROR, throwsStateError);
      });
      root.level = Level.WARN;
      expect(root.level, Level.ERROR);
    });
  });
}
