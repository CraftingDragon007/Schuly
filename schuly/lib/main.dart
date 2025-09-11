import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/start_page.dart';
import 'pages/agenda_page.dart';
import 'pages/notes_page.dart';
import 'pages/absenzen_page.dart';
import 'pages/account_page.dart';
import 'pages/login_page.dart';
import 'pages/student_card_page.dart';
import 'providers/theme_provider.dart';
import 'providers/api_store.dart';
import 'providers/homepage_config_provider.dart';
import 'services/storage_service.dart';
import 'services/push_notification_service.dart';
import 'widgets/homepage_config_modal.dart';
import 'widgets/release_notes_dialog.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/comprehensive_permission_modal.dart';
import 'package:schuly/api/lib/api.dart';

String apiBaseUrl = 'https://schulware.pianonic.ch';

Future<void> loadApiBaseUrl() async {
  final storedUrl = await StorageService.getApiUrl();
  if (storedUrl != null && storedUrl.isNotEmpty) {
    apiBaseUrl = storedUrl;
    defaultApiClient = ApiClient(basePath: apiBaseUrl);
  }
}

Future<void> setApiBaseUrl(String url) async {
  apiBaseUrl = url;
  defaultApiClient = ApiClient(basePath: url);
  await StorageService.setApiUrl(url);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize push notifications
  await PushNotificationService.initialize();
  
  await loadApiBaseUrl();
  final apiStore = ApiStore();
  await apiStore.loadUsers();
  await apiStore.autoLoginIfNeeded();
  defaultApiClient = ApiClient(basePath: apiBaseUrl);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => apiStore),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => HomepageConfigProvider()),
      ],
      child: const SchulyApp(),
    ),
  );
}

class SchulyApp extends StatelessWidget {
  const SchulyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Consumer<ApiStore>(
      builder: (context, apiStore, _) {
        if (apiStore.userEmails.isEmpty) {
          // Wrap LoginPage in MaterialApp with theming
          return MaterialApp(
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: LoginPage(
              onApiBaseUrlChanged: (url) async {
                await setApiBaseUrl(url);
              },
              initialApiBaseUrl: apiBaseUrl,
            ),
          );
        }
        return MaterialApp(
          title: 'schulNetz',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          home: MyHomePage(title: 'schulNetz', themeProvider: themeProvider),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.themeProvider,
  });

  final String title;
  final ThemeProvider themeProvider;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final apiStore = Provider.of<ApiStore>(context, listen: false);
    if (apiStore.userEmails.isNotEmpty && apiStore.activeUserEmail != null) {
      apiStore.fetchAll();
    }
    
    // Show app update dialog and release notes dialog if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check for app updates first (higher priority)
      await AppUpdateDialog.showIfAvailable(context);
      
      // Then check for release notes
      if (context.mounted) {
        await ReleaseNotesDialog.showIfNeeded(context);
      }
      
      // Show comprehensive permission modal if needed
      if (context.mounted) {
        await _showComprehensivePermissionsIfNeeded();
      }
    });
  }

  Future<void> _showComprehensivePermissionsIfNeeded() async {
    // Check if we should show the comprehensive permission modal
    final showPermissionModal = await _shouldShowPermissionModal();
    
    if (showPermissionModal && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false, // Force user interaction
        builder: (context) => const ComprehensivePermissionModal(),
      );
    }
  }

  Future<bool> _shouldShowPermissionModal() async {
    // Check if basic notification permissions are granted
    final permissionsGranted = await PushNotificationService.arePermissionsGranted();
    
    // If basic permissions are missing, definitely show the modal
    if (!permissionsGranted) {
      return true;
    }

    // Check if user has any notification types enabled but permissions might be incomplete
    final agendaEnabled = await StorageService.getNotificationEnabled('agenda') ?? true;
    final gradesEnabled = await StorageService.getNotificationEnabled('grades') ?? false;
    final absencesEnabled = await StorageService.getNotificationEnabled('absences') ?? false;
    
    // If user has notifications enabled, they might benefit from the comprehensive modal
    // But only show it occasionally to avoid being annoying
    if (agendaEnabled || gradesEnabled || absencesEnabled) {
      // Check if we've shown this modal recently (store a timestamp)
      final lastShown = await StorageService.getLastPermissionModalShown();
      final now = DateTime.now();
      
      // Show modal if never shown or if it's been more than 7 days
      if (lastShown == null || now.difference(lastShown).inDays > 7) {
        // Store that we're about to show it
        await StorageService.setLastPermissionModalShown(now);
        return true;
      }
    }
    
    return false;
  }

  // 2. _onItemTapped is simplified
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // 3. _onPageChanged is removed as it was only for PageView

  // This method still works perfectly for navigating from the StartPage
  void navigateToPage(int index) {
    _onItemTapped(index);
  }

  void _showHomepageConfigDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAliasWithSaveLayer,
      builder: (context) => const HomepageConfigModal(),
    );
  }


  @override
  Widget build(BuildContext context) {
    // 4. A list of pages is created to be indexed
    final List<Widget> pages = [
      StartPage(onNavigateToAbsenzen: () => navigateToPage(3)),
      const AgendaPage(),
      const NotesPage(),
      const AbsenzenPage(),
      AccountPage(themeProvider: widget.themeProvider),
    ];

    // Page titles for the header
    final List<String> pageTitles = [
      'Start',
      'Agenda',
      'Noten',
      'Absenzen',
      'Account',
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          pageTitles[_selectedIndex],
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.normal,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: _selectedIndex == 0 ? [
          // Homepage configuration icon
          IconButton(
            onPressed: () {
              _showHomepageConfigDialog(context);
            },
            icon: Icon(
              Icons.tune,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'Start-Seite anpassen',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StudentCardPage()),
              );
            },
            icon: Icon(
              Icons.badge_outlined,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'Schülerausweis',
          ),
        ] : _selectedIndex != 4 ? [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StudentCardPage()),
              );
            },
            icon: Icon(
              Icons.badge_outlined,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'Schülerausweis',
          ),
        ] : null,
      ),
      // 5. PageView is replaced with animated page transitions
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: Container(
          key: ValueKey(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final appColors = Theme.of(context).extension<AppColors>();
          final seedColor = appColors?.seedColor ?? Theme.of(context).colorScheme.primary;
          
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            animationDuration: const Duration(milliseconds: 300),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, 
                  color: _selectedIndex == 0 ? seedColor : null),
                selectedIcon: Icon(Icons.home, color: seedColor),
                label: 'Start',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined,
                  color: _selectedIndex == 1 ? seedColor : null),
                selectedIcon: Icon(Icons.calendar_today, color: seedColor),
                label: 'Agenda',
              ),
              NavigationDestination(
                icon: Icon(Icons.grade_outlined,
                  color: _selectedIndex == 2 ? seedColor : null),
                selectedIcon: Icon(Icons.grade, color: seedColor),
                label: 'Noten',
              ),
              NavigationDestination(
                icon: Icon(Icons.list_alt_outlined,
                  color: _selectedIndex == 3 ? seedColor : null),
                selectedIcon: Icon(Icons.list_alt, color: seedColor),
                label: 'Absenzen',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline,
                  color: _selectedIndex == 4 ? seedColor : null),
                selectedIcon: Icon(Icons.person, color: seedColor),
                label: 'Account',
              ),
            ],
          );
        },
      ),
    );
  }
}