import 'package:cafe_andalus_menu/models/branch.dart';
import 'package:cafe_andalus_menu/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // addToCart отзывается лёгкой вибрацией, а для неё нужен канал к платформе
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // Одна функция на экран, сообщение и админку. Раньше экран отрезал
  // дробную часть, а сообщение округляло: в корзине «649 с.», в WhatsApp
  // «649.90 с.», и слагаемые не сходились с итогом
  group('показ суммы', () {
    test('целое — без хвоста', () {
      expect(money(280), '280');
      expect(money(0), '0');
    });

    test('дробное округляется, а не отрезается', () {
      expect(money(649.9), '649.90');
      expect(money(100.6 + 100.6), '201.20');
      expect(money(0.005), '0.01');
    });

    test('копеечный хвост от умножения не вылезает наружу', () {
      expect(money(0.1 * 3), '0.30');
    });
  });

  group('пределы корзины', () {
    setUp(() => globalCart.value = []);
    tearDown(() => globalCart.value = []);

    final dish = Product(id: 'p1', parentId: '', name: 'Лагман', price: 280);

    test('больше 99 порций одного блюда не кладётся', () {
      expect(addToCart(dish, null, 98), AddToCart.added);
      expect(addToCart(dish, null, 5), AddToCart.added);
      expect(globalCart.value.single.quantity, maxCartQuantity);
      // Дальше — отказ, а не молчаливое превышение: сервер такой заказ
      // не примет, а сообщение в WhatsApp к тому времени уже уйдёт
      expect(addToCart(dish, null, 1), AddToCart.tooManyOfOne);
      expect(globalCart.value.single.quantity, maxCartQuantity);
    });

    test('больше 100 разных блюд не кладётся', () {
      for (var i = 0; i < maxCartLines; i++) {
        final p = Product(id: 'p$i', parentId: '', name: 'Блюдо $i', price: 10);
        expect(addToCart(p, null, 1), AddToCart.added, reason: 'строка $i');
      }
      final extra = Product(id: 'x', parentId: '', name: 'Лишнее', price: 10);
      expect(addToCart(extra, null, 1), AddToCart.tooManyLines);
      expect(globalCart.value.length, maxCartLines);
    });

    test('у занятой строки предел не мешает добрать количество', () {
      expect(addToCart(dish, null, 1), AddToCart.added);
      expect(addToCart(dish, null, 1), AddToCart.added);
      expect(globalCart.value.single.quantity, 2);
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
