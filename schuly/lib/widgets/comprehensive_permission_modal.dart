import 'package:flutter/material.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';

enum PermissionStatus {
  granted,
  denied,
  notRequested,
  unknown
}

class PermissionInfo {
  final String name;
  final String description;
  final IconData icon;
  final PermissionStatus status;
  final bool isRequired;
  final bool isRecommended;

  PermissionInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.status,
    required this.isRequired,
    required this.isRecommended,
  });
}

class ComprehensivePermissionModal extends StatefulWidget {
  const ComprehensivePermissionModal({super.key});

  @override
  State<ComprehensivePermissionModal> createState() => _ComprehensivePermissionModalState();
}

class _ComprehensivePermissionModalState extends State<ComprehensivePermissionModal> with WidgetsBindingObserver {
  List<PermissionInfo> _permissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh permission status when user returns to the app
      _loadPermissionStatus();
    }
  }

  Future<void> _loadPermissionStatus() async {
    final permissions = <PermissionInfo>[];

    // Basic notification permission
    final notificationGranted = await PushNotificationService.arePermissionsGranted();
    permissions.add(PermissionInfo(
      name: 'Benachrichtigungen',
      description: 'Grundlegende Berechtigung zum Anzeigen von Benachrichtigungen',
      icon: Icons.notifications_outlined,
      status: notificationGranted ? PermissionStatus.granted : PermissionStatus.denied,
      isRequired: true,
      isRecommended: true,
    ));

    // Android specific permissions
    if (Platform.isAndroid) {
      // Exact alarm permission (critical for notifications)
      try {
        final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
        permissions.add(PermissionInfo(
          name: 'Exakte Benachrichtigungen',
          description: 'Erforderlich für präzise Benachrichtigungen zur richtigen Zeit (Android 12+)',
          icon: Icons.schedule_outlined,
          status: exactAlarmStatus.isGranted ? PermissionStatus.granted : PermissionStatus.denied,
          isRequired: true,
          isRecommended: true,
        ));
      } catch (e) {
        permissions.add(PermissionInfo(
          name: 'Exakte Benachrichtigungen',
          description: 'Erforderlich für präzise Benachrichtigungen zur richtigen Zeit (Android 12+)',
          icon: Icons.schedule_outlined,
          status: PermissionStatus.unknown,
          isRequired: true,
          isRecommended: true,
        ));
      }

      // Battery optimization
      try {
        final batteryOptStatus = await Permission.ignoreBatteryOptimizations.status;
        permissions.add(PermissionInfo(
          name: 'Batterie-Optimierung umgehen',
          description: 'Verbessert die Zuverlässigkeit von Benachrichtigungen im Hintergrund',
          icon: Icons.battery_saver_outlined,
          status: batteryOptStatus.isGranted ? PermissionStatus.granted : PermissionStatus.denied,
          isRequired: false,
          isRecommended: true,
        ));
      } catch (e) {
        permissions.add(PermissionInfo(
          name: 'Batterie-Optimierung umgehen',
          description: 'Verbessert die Zuverlässigkeit von Benachrichtigungen im Hintergrund',
          icon: Icons.battery_saver_outlined,
          status: PermissionStatus.unknown,
          isRequired: false,
          isRecommended: true,
        ));
      }

      // App background activity (this is more complex to check directly)
      permissions.add(PermissionInfo(
        name: 'Hintergrund-Aktivität',
        description: 'Ermöglicht der App, im Hintergrund aktiv zu bleiben',
        icon: Icons.play_arrow_outlined,
        status: PermissionStatus.unknown,
        isRequired: false,
        isRecommended: true,
      ));
    }

    setState(() {
      _permissions = permissions;
      _isLoading = false;
    });
  }


  Future<void> _requestNotificationPermission() async {
    try {
      final granted = await PushNotificationService.requestPermissions();
      
      if (granted) {
        await StorageService.setNotificationEnabled('agenda', true);
        await StorageService.setPushNotificationsEnabled(true);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Benachrichtigungen aktiviert!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Berechtigung verweigert. Prüfen Sie die Geräte-Einstellungen.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      
      await _loadPermissionStatus();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Anfordern der Berechtigung.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      // First try to request the permission
      final status = await Permission.ignoreBatteryOptimizations.request();
      
      if (context.mounted) {
        if (status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Batterie-Optimierung erfolgreich deaktiviert!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // If permission request fails, open device settings
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Öffne Geräte-Einstellungen für Batterie-Optimierung...'),
              duration: Duration(seconds: 3),
            ),
          );
          
          // Open device battery optimization settings
          await openAppSettings();
        }
      }
      
      await _loadPermissionStatus();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Öffne App-Einstellungen...'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Fallback to app settings
        await openAppSettings();
        await _loadPermissionStatus();
      }
    }
  }

  Future<void> _requestBackgroundActivity() async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Öffne App-Einstellungen...\n\nSuchen Sie nach:\n• "Batterie" → App nicht optimieren\n• "Autostart" oder "Hintergrund-App-Refresh"\n• "Datennutzung" → Hintergrunddaten erlauben'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 5),
          ),
        );
      }
      
      // Wait a moment for user to read the message
      await Future.delayed(const Duration(milliseconds: 1500));
      
      // Open app settings where users can manually enable background activity
      await openAppSettings();
      
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konnte App-Einstellungen nicht öffnen.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _requestExactAlarmsPermission() async {
    try {
      final status = await Permission.scheduleExactAlarm.request();
      
      if (context.mounted) {
        if (status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exakte Benachrichtigungen aktiviert!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Öffne Einstellungen für exakte Benachrichtigungen...'),
              duration: Duration(seconds: 3),
            ),
          );
          await openAppSettings();
        }
      }
      
      await _loadPermissionStatus();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Öffne App-Einstellungen für exakte Benachrichtigungen...'),
            duration: Duration(seconds: 2),
          ),
        );
        await openAppSettings();
        await _loadPermissionStatus();
      }
    }
  }

  void _getPermissionAction(String permissionName) {
    switch (permissionName) {
      case 'Benachrichtigungen':
        _requestNotificationPermission();
        break;
      case 'Exakte Benachrichtigungen':
        _requestExactAlarmsPermission();
        break;
      case 'Batterie-Optimierung umgehen':
        _requestBatteryOptimization();
        break;
      case 'Hintergrund-Aktivität':
        _requestBackgroundActivity();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Benachrichtigungs-Berechtigungen',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Für die beste Erfahrung empfehlen wir, alle relevanten Berechtigungen zu gewähren.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Permission List
            Flexible(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _permissions.length,
                      itemBuilder: (context, index) {
                        final permission = _permissions[index];
                        final isGranted = permission.status == PermissionStatus.granted;
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isGranted 
                                ? Colors.green.withValues(alpha: 0.3)
                                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                permission.icon,
                                color: isGranted 
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      permission.name,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      permission.description,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (isGranted)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                )
                              else
                                SizedBox(
                                  height: 36,
                                  child: ElevatedButton(
                                    onPressed: () => _getPermissionAction(permission.name),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: Text(
                                      'Aktivieren',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Fertig'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}