import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';

// Копия lib/picker_options_web.dart приложения меню: super_admin — отдельный
// пакет, и он только веб, поэтому без условного импорта.

/// Выбор файла в браузере.
///
/// `cancelUploadOnWindowBlur` по умолчанию включён: как только страница
/// снова получает фокус, выбор считается отменённым, и файл ждут всего
/// пол секунды. На айфоне фокус возвращается раньше, чем Safari отдаёт
/// снимок (он ещё переводит HEIC в JPEG — на 12 Мп это дольше полсекунды),
/// поэтому выбор фото молча превращался в «отменено» и ничего
/// не загружалось. В Chrome на Android файл приходит сразу, там не видно.
///
/// Выключаем: окно потеряло фокус — просто ждём файл или настоящую отмену
/// (событие `cancel` самого поля).
const WebOptions pickerWebOptions = FilePickerWebOptions(
  cancelUploadOnWindowBlur: false,
);
