import 'api/api_client.dart';
import 'models/branch.dart';

/// Меню гостя берётся из `menu_store.dart`; здесь — только то, что нужно
/// админке кафе.
class DatabaseService {
  /// Филиалы кафе, в которое вошёл администратор, в порядке поля «Порядок».
  ///
  /// Гостю список всех филиалов не отдаётся: в базе лежат меню разных
  /// кафе, и гость попадает в своё только по ссылке из QR-кода.
  ///
  /// Ошибку не прячет: «нет связи» и «филиалов нет» вызывающий должен
  /// показать по-разному.
  Future<List<Branch>> getBranches() async {
    final data = await api.list('/api/admin/branches');
    return data.map(Branch.fromJson).toList();
  }
}
