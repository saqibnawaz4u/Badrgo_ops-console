import 'maintenance_info.dart';

sealed class HealthResult {
  const HealthResult();
}

class HealthUp extends HealthResult {
  const HealthUp();
}

class HealthMaintenance extends HealthResult {
  const HealthMaintenance(this.info);
  final MaintenanceInfo info;
}

class HealthUnreachable extends HealthResult {
  const HealthUnreachable();
}

abstract interface class HealthRepository {
  /// `GET /api/health`. Never throws.
  Future<HealthResult> check();
}
