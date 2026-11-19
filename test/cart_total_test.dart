import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('суммы корзины', () {
    final cart = [
      CartItem(
        product: Product(id: 'p1', parentId: '', name: 'Лагман', price: 280),
        portion: Portion(name: 'большая', price: 320),
        quantity: 2,
      ),
      CartItem(
        product: Product(id: 'p2', parentId: '', name: 'Чай', price: 120),
        quantity: 3,
      ),
    ];

    test('цена порции важнее цены блюда', () {
      expect(cartTotal(cart), 320 * 2 + 120 * 3);
    });

    test('количество считается по всем позициям', () {
      expect(cartCount(cart), 5);
    });

    test('пустая корзина — нули, а не ошибка', () {
      expect(cartTotal(const []), 0);
      expect(cartCount(const []), 0);
    });
  });

  group('филиал: заказы', () {
    test('поля заказа читаются с сервера', () {
      final b = Branch.fromJson({
        'id': 'b1',
        'slug': 'center',
        'name': 'Центр',
        'order_whatsapp': '996555112233',
        'delivery_price': 150,
      });
      expect(b.orderWhatsapp, '996555112233');
      expect(b.deliveryPrice, 150);
      expect(b.canOrderByWhatsapp, isTrue);
    });

    test('сохранённая копия меню от старой версии — заказов просто нет', () {
      final b = Branch.fromJson({'id': 'b1', 'slug': 'center', 'name': 'Центр'});
      expect(b.orderWhatsapp, '');
      expect(b.deliveryPrice, 0);
      expect(b.canOrderByWhatsapp, isFalse);
    });

    test('испорченный номер не считается рабочим', () {
      for (final bad in ['', '12345', '+996555112233', 'телефон']) {
        final b = Branch.fromJson({
          'id': 'b1',
          'slug': 'center',
          'name': 'Центр',
          'order_whatsapp': bad,
        });
        expect(b.canOrderByWhatsapp, isFalse, reason: bad);
      }
    });
  });
}
