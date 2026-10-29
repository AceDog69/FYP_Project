import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fyp_app/models/public_queue_count.dart';
import 'package:my_fyp_app/services/order_repository.dart';
import 'package:my_fyp_app/screens/student_home.dart';
import 'package:my_fyp_app/theme/app_theme.dart';
import 'package:my_fyp_app/widgets/stall_queue_count.dart';
import 'support/catalog_fixtures.dart';
import 'support/fake_catalog_repository.dart';

Map<String, dynamic> data(String uid, int last, int next, bool preparing) => {
  ...queueCountFields(uid, last, next, preparing), 'updatedAt': Timestamp.now(),
};
class _NoNetworkFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected Firebase access');
}
class _Catalog extends FakeCatalogRepository {
  final counts = <String, Map<String, dynamic>?>{};
  final reads = <String, int>{};
  bool countCached = false, countLoading = false;
  String? countError;
  @override
  Stream<PublicQueueCount?> queueCount(String vendorUid) async* {
    reads.update(vendorUid, (n) => n + 1, ifAbsent: () => 1);
    PublicQueueCount? value() => PublicQueueCount.decode(vendorUid, counts[vendorUid], cached: countCached);
    if (!countLoading) yield value();
    await for (final _ in events.stream) {
      if (countError == vendorUid) { yield* Stream<PublicQueueCount?>.error(StateError('offline')); }
      else { yield value(); }
    }
  }
}

void main() {
  test('default repository keeps Stage 4B opt-in and existing write gates disabled without Firebase access', () {
    final repository = FirebaseOrderRepository(_NoNetworkFirestore(), () => 'student');
    expect(repository.usesPublicQueueCounts,false); expect(repository.canCheckout,false); expect(repository.canProcessOrders,false);
  });
  test('confirmed ticket and single-slot cursor formula covers every count transition', () {
    expect(PublicQueueCount.decode('v', data('v',0,1,false))!.count,0);
    expect(PublicQueueCount.decode('v', data('v',1,1,false))!.count,1);
    expect(PublicQueueCount.decode('v', data('v',3,1,false))!.count,3);
    expect(PublicQueueCount.decode('v', data('v',3,2,true))!.count,3);
    expect(PublicQueueCount.decode('v', data('v',3,2,false))!.count,2);
    expect(PublicQueueCount.decode('v', data('v',3,4,false))!.count,0);
  });
  test('missing is unknown; mismatched vendor, count, schema, private fields or timestamps are rejected', () {
    expect(PublicQueueCount.decode('v',null),isNull);
    final valid = data('v',1,1,false);
    for (final bad in [<String,dynamic>{}, {...valid,'count':0}, {...valid,'count':1.0}, {...valid,'vendorUid':'other'},
      {...valid,'lastTicket':'1'}, {...valid,'lastTicket':1.0}, {...valid,'nextTicket':1.0},
      {...valid,'schemaVersion':1.0}, {...valid,'schemaVersion':2}, {...valid,'updatedAt':'old'},
      {...valid,'lastOrderId':'private'}, {...valid,'studentUid':'private'}, {...valid}..remove('preparing')]) {
      expect(() => PublicQueueCount.decode('v',bad),throwsFormatException);
    }
  });
  test('bounds reject impossible cursor state and preserve safe integer maximum', () {
    for (final args in [(0,2,false),(0,1,true),(-1,1,false),(2147483648,1,false),(1,0,false)]) {
      expect(() => queueCountFields('v',args.$1,args.$2,args.$3),throwsFormatException);
    }
    expect(PublicQueueCount.decode('v',data('v',2147483647,2147483648,false))!.count,0);
    expect(PublicQueueCount.decode('v',data('v',1,1,false),cached:true)!.cached,true);
  });

  Future<void> mount(WidgetTester tester, Widget screen, {Size size = const Size(412,915), double scale = 1}) async {
    await tester.binding.setSurfaceSize(size); addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme:smartCanteenTheme(),home:MediaQuery(
      data:MediaQueryData(size:size,textScaler:TextScaler.linear(scale)),child:Scaffold(body:screen))));
    await tester.pump(); await tester.pump();
  }
  _Catalog catalog() {
    final repo = _Catalog(); populate(repo); addTearDown(repo.dispose); return repo;
  }
  testWidgets('Home shows a verified zero to a Student with no orders and leaves navigation unchanged', (tester) async {
    final repo = catalog(); repo.counts['alpha'] = data('alpha',0,1,false); String? selected;
    await mount(tester,StudentHome(repository:repo,onStall:(s) => selected = s.id)); await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('stall-alpha'));
    expect(find.descendant(of:card,matching:find.text('Orders in queue: 0')),findsOneWidget);
    expect(find.textContaining('Approx.'),findsNothing);
    final action = find.descendant(of:card,matching:find.widgetWithText(FilledButton,'View Menu'));
    await tester.ensureVisible(action); await tester.tap(action); await tester.pumpAndSettle(); expect(selected,'alpha');
    expect(tester.getSize(action).height,greaterThanOrEqualTo(48));
  });
  testWidgets('live independent counts change without resubscribing on search/filter rebuilds', (tester) async {
    final repo = catalog(); repo.counts['alpha'] = data('alpha',1,1,false); repo.counts['beta'] = data('beta',4,2,false);
    await mount(tester,StudentHome(repository:repo,onStall:(_) {})); await tester.pumpAndSettle();
    expect(find.text('Orders in queue: 1'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'Alpha'); await tester.pumpAndSettle(); expect(repo.reads['alpha'],1);
    repo.counts['alpha'] = data('alpha',2,2,true); repo.emit(); await tester.pumpAndSettle(); expect(find.text('Orders in queue: 2'),findsOneWidget);
    repo.counts['alpha'] = data('alpha',2,2,false); repo.emit(); await tester.pumpAndSettle(); expect(find.text('Orders in queue: 1'),findsOneWidget);
    await tester.tap(find.byTooltip('Clear search')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('home-queue-count-beta')));
    expect(find.text('Orders in queue: 3'),findsOneWidget);
  });
  testWidgets('loading missing cached and stale-stall count never imply zero', (tester) async {
    final repo = catalog()..countLoading = true;
    await mount(tester,StallQueueCount(vendorUid:'alpha',repository:repo,currentStall:true));
    expect(find.text('Queue unavailable'),findsOneWidget);
    repo.countLoading = false; repo.emit(); await tester.pumpAndSettle(); expect(find.text('Queue unavailable'),findsOneWidget);
    repo.counts['alpha'] = data('alpha',0,1,false); repo.countCached = true; repo.emit(); await tester.pumpAndSettle();
    expect(find.text('Queue unavailable'),findsOneWidget);
    repo.countCached = false; repo.emit(); await tester.pumpAndSettle(); expect(find.text('Orders in queue: 0'),findsOneWidget);
    await mount(tester,StallQueueCount(vendorUid:'alpha',repository:repo,currentStall:false)); await tester.pumpAndSettle();
    expect(find.text('Queue unavailable'),findsOneWidget);
  });
  testWidgets('malformed and denied/error aggregate produce unavailable without breaking stall browsing', (tester) async {
    final repo = catalog(); repo.counts['alpha'] = {...data('alpha',2,1,false),'count':0};
    await mount(tester,StudentHome(repository:repo,onStall:(_) {})); await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('stall-alpha'));
    expect(find.descendant(of:card,matching:find.text('Queue unavailable')),findsOneWidget);
    expect(find.descendant(of:card,matching:find.widgetWithText(FilledButton,'View Menu')),findsOneWidget);
    await mount(tester,StallQueueCount(vendorUid:'beta',repository:repo,currentStall:true)); await tester.pumpAndSettle();
    repo.countError = 'beta'; repo.emit(); await tester.pumpAndSettle(); expect(find.text('Queue unavailable'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('replacing repository or stall clears retained values while next stream loads', (tester) async {
    final first = catalog(); first.counts['alpha'] = data('alpha',2,1,false);
    await mount(tester,StallQueueCount(vendorUid:'alpha',repository:first,currentStall:true)); await tester.pumpAndSettle();
    expect(find.text('Orders in queue: 2'),findsOneWidget);
    final next = catalog()..countLoading = true;
    await mount(tester,StallQueueCount(vendorUid:'beta',repository:next,currentStall:true));
    expect(find.text('Orders in queue: 2'),findsNothing); expect(find.text('Queue unavailable'),findsOneWidget);
    await mount(tester,const StallQueueCount(vendorUid:'beta',repository:null,currentStall:true)); await tester.pumpAndSettle();
    expect(find.text('Queue unavailable'),findsOneWidget);
  });
  testWidgets('Home remains scrollable at 320x640 with large text, search and category navigation', (tester) async {
    final repo = catalog(); repo.counts['closed'] = data('closed',2147483647,1,false); String? selected;
    await mount(tester,StudentHome(repository:repo,onStall:(s) => selected = s.id),size:const Size(320,640),scale:1.6);
    await tester.pumpAndSettle(); final chip = find.widgetWithText(ChoiceChip,'Chinese');
    await tester.ensureVisible(chip); await tester.tap(chip); await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton,'View Menu');
    await tester.scrollUntilVisible(action,200,scrollable:find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    await tester.tap(action); await tester.pumpAndSettle(); expect(selected,'closed');
    expect(find.text('Orders in queue: 2147483647'),findsOneWidget); expect(tester.takeException(),isNull);
  });
}
