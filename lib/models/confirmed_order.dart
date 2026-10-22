import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/checkout_limits.dart';
import '../constants/predefined_pictures.dart';

const simulatedPaymentMethods = {'ewallet': 'E-Wallet', 'onlineBanking': 'Online Banking', 'card': 'Credit / Debit Card'};

class OrderItem {
  const OrderItem({required this.foodId, required this.name, required this.description,
    required this.categoryId, required this.pictureId, required this.priceSen,
    required this.quantity, required this.foodRevision, this.categoryName = ''});
  final String foodId, name, description, categoryId, pictureId, categoryName;
  final int priceSen, quantity, foodRevision;
  int get subtotalSen => priceSen * quantity;
  Map<String, dynamic> get draftMap => {'foodId': foodId, 'name': name, 'description': description,
    'categoryId': categoryId, 'pictureId': pictureId, 'priceSen': priceSen,
    'quantity': quantity, 'foodRevision': foodRevision};
  Map<String, dynamic> get snapshotMap => {...draftMap, 'categoryName': categoryName, 'subtotalSen': subtotalSen};
  factory OrderItem.decode(Map<String, dynamic> d, {bool snapshot = false}) {
    if (['foodId','name','description','categoryId','pictureId'].any((k) => d[k] is! String) ||
        (d['foodId'] as String).isEmpty || (d['foodId'] as String).length > 128 || (d['foodId'] as String).contains('/') ||
        (d['categoryId'] as String).isEmpty || (d['categoryId'] as String).length > 128 || (d['categoryId'] as String).contains('/') ||
        (d['name'] as String).trim().isEmpty || (d['name'] as String).length > 100 ||
        (d['description'] as String).trim().isEmpty || (d['description'] as String).length > 500 ||
        d['priceSen'] is! int || d['priceSen'] < 1 || d['priceSen'] > 100000 ||
        d['quantity'] is! int || d['quantity'] < 1 || d['quantity'] > maxCheckoutQuantity ||
        d['foodRevision'] is! int || d['foodRevision'] < 1 ||
        !predefinedPictures.containsKey(d['pictureId']) ||
        (snapshot && (d['categoryName'] is! String || (d['categoryName'] as String).trim().isEmpty ||
          (d['categoryName'] as String).length > 50 || d['subtotalSen'] != d['priceSen'] * d['quantity']))) {
      throw const FormatException('Invalid order item.');
    }
    return OrderItem(foodId: d['foodId'], name: d['name'], description: d['description'],
      categoryId: d['categoryId'], pictureId: d['pictureId'], priceSen: d['priceSen'],
      quantity: d['quantity'], foodRevision: d['foodRevision'], categoryName: d['categoryName'] ?? '');
  }
}

class CheckoutRequest {
  CheckoutRequest({required this.id, required this.studentUid, required this.vendorUid,
    required this.stallName, required List<OrderItem> items, required this.paymentMethod,
    this.state = 'pending', this.createdAt}) : items = List.unmodifiable(items) {
    if (!RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id) || items.isEmpty || items.length > maxCheckoutProducts ||
        studentUid.isEmpty || studentUid.length > 128 || vendorUid.isEmpty || vendorUid.length > 128 || vendorUid.contains('/') ||
        stallName.trim().isEmpty || stallName.length > 100 ||
        items.map((i) => i.foodId).toSet().length != items.length ||
        !simulatedPaymentMethods.containsKey(paymentMethod)) {
          throw const FormatException('Invalid checkout request.');
        }
    for (final item in items) { OrderItem.decode(item.draftMap); }
  }
  final String id, studentUid, vendorUid, stallName, paymentMethod, state;
  final List<OrderItem> items;
  final Timestamp? createdAt;
  int get totalSen => items.fold(0, (total, i) => total + i.subtotalSen);
  Map<String, dynamic> createMap({String state = 'pending'}) => {
    'schemaVersion': 1, 'submissionId': id, 'studentUid': studentUid, 'vendorUid': vendorUid,
    'stallName': stallName, 'items': items.map((i) => i.draftMap).toList(), 'totalSen': totalSen,
    'paymentMethod': paymentMethod, 'state': state,
    'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
  };
  factory CheckoutRequest.decode(String id, Map<String, dynamic> d) {
    if (d['schemaVersion'] != 1 || d['submissionId'] != id || d['createdAt'] is! Timestamp ||
        d['updatedAt'] is! Timestamp || !['pending','confirmed','cancelled'].contains(d['state']) ||
        d['items'] is! List || ['studentUid','vendorUid','stallName','paymentMethod'].any((k) => d[k] is! String)) {
      throw const FormatException('Invalid checkout record.');
    }
    final request = CheckoutRequest(id: id, studentUid: d['studentUid'], vendorUid: d['vendorUid'],
      stallName: d['stallName'], paymentMethod: d['paymentMethod'], state: d['state'], createdAt: d['createdAt'],
      items: (d['items'] as List).map((i) => OrderItem.decode(Map<String, dynamic>.from(i as Map))).toList());
    if (d['totalSen'] != request.totalSen) {
      throw const FormatException('Invalid checkout total.');
    }
    return request;
  }
}

const orderStatuses = ['Pending', 'Preparing', 'Ready', 'Completed'];

class ConfirmedOrder {
  ConfirmedOrder({required this.id, required this.studentUid, required this.vendorUid,
    required this.stallName, required this.ticket, required this.totalSen, required this.itemCount,
    required this.preparationMinutes, required this.paymentMethod, required this.createdAt,
    required this.firstItem, this.status = 'Pending', this.statusRevision = 0,
    this.statusUpdatedAt, this.preparingAt, this.readyAt, this.completedAt}) {
    if (itemCount < 1 || itemCount > maxCheckoutProducts) {
      throw const FormatException('Invalid confirmed order size.');
    }
  }
  final String id, studentUid, vendorUid, stallName, paymentMethod, status;
  final int ticket, totalSen, itemCount, preparationMinutes, statusRevision;
  final Timestamp? statusUpdatedAt, preparingAt, readyAt, completedAt;
  String? get nextStatus => status == 'Completed' ? null : orderStatuses[orderStatuses.indexOf(status) + 1];
  final Timestamp createdAt;
  final OrderItem firstItem;
  factory ConfirmedOrder.decode(String id, Map<String, dynamic> d) {
    if (d['schemaVersion'] != 1 || d['orderId'] != id || d['submissionId'] != id || !orderStatuses.contains(d['status']) ||
        d['paymentStatus'] != 'simulated' || d['ticket'] is! int || d['ticket'] < 1 ||
        d['itemCount'] is! int || d['itemCount'] < 1 || d['itemCount'] > maxCheckoutProducts ||
        d['totalSen'] is! int || d['totalSen'] < 1 || d['preparationMinutes'] is! int ||
        d['preparationMinutes'] < 1 || d['preparationMinutes'] > 180 || d['ticket'] > 2147483647 ||
        d['createdAt'] is! Timestamp || d['firstItem'] is! Map ||
        ['studentUid','vendorUid','stallName','paymentMethod'].any((k) => d[k] is! String) ||
        !simulatedPaymentMethods.containsKey(d['paymentMethod'])) {
          throw const FormatException('Invalid confirmed order.');
        }
    final revision = orderStatuses.indexOf(d['status'] as String);
    if ((d['statusRevision'] ?? 0) != revision ||
        (revision > 0 && (d['statusUpdatedAt'] is! Timestamp || d['preparingAt'] is! Timestamp)) ||
        (revision > 1 && d['readyAt'] is! Timestamp) || (revision > 2 && d['completedAt'] is! Timestamp)) {
      throw const FormatException('Invalid order progress.');
    }
    return ConfirmedOrder(id: id, studentUid: d['studentUid'], vendorUid: d['vendorUid'], stallName: d['stallName'],
      ticket: d['ticket'], totalSen: d['totalSen'], itemCount: d['itemCount'], preparationMinutes: d['preparationMinutes'],
      paymentMethod: d['paymentMethod'], createdAt: d['createdAt'],
      status: d['status'], statusRevision: revision, statusUpdatedAt: d['statusUpdatedAt'],
      preparingAt: d['preparingAt'], readyAt: d['readyAt'], completedAt: d['completedAt'],
      firstItem: OrderItem.decode(Map<String, dynamic>.from(d['firstItem'] as Map), snapshot: true));
  }
}

class OrderReceipt {
  OrderReceipt(this.order, List<OrderItem> items) : items = List.unmodifiable(items) {
    if (items.isEmpty || items.length > maxCheckoutProducts || items.length != order.itemCount ||
        items.map((i) => i.foodId).toSet().length != items.length ||
        items.fold<int>(0, (s, i) => s + i.subtotalSen) != order.totalSen) {
      throw const FormatException('Incomplete confirmed order.');
    }
  }
  final ConfirmedOrder order;
  final List<OrderItem> items;
}
