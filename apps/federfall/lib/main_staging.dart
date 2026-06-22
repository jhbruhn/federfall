import 'package:federfall/app/app.dart';
import 'package:federfall/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
