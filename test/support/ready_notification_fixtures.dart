import 'package:my_fyp_app/models/confirmed_order.dart';
import 'fake_order_repository.dart';

OrderReceipt notificationReceipt(String id, {String student = 'student', String vendor = 'alpha',
  int ticket = 1, String status = 'Pending', String? stallName}) {
  final request = CheckoutRequest(id: id.padLeft(20, '0'), studentUid: student, vendorUid: vendor,
    stallName: stallName ?? '$vendor Kitchen', paymentMethod: 'ewallet', items: [
      const OrderItem(foodId: 'rice', name: 'Rice Bowl', description: 'Fresh rice', categoryId: 'meals',
        pictureId: 'nasi_lemak', priceSen: 850, quantity: 2, foodRevision: 1),
    ]);
  final receipt = receiptFor(request, ticket); var order = receipt.order;
  while (order.status != status) { order = progressed(order); }
  return OrderReceipt(order, receipt.items);
}
