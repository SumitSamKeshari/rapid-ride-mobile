import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../config.dart';
import '../services/logger_service.dart';
import 'login_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  HubConnection? _hubConnection;
  bool _isConnected = false;
  int? _activeRideId;
  int _driverId = 0;

  StreamSubscription<Position>? _positionStreamSubscription;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _initDriverSession();
  }

  Future<void> _initDriverSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _driverId = prefs.getInt('user_id') ?? 0;
      await _startSignalRConnection();
    } catch (e, stack) {
      AppLogger.error('DriverMap', 'Session initialization error', e, stack);
    }
  }

  Future<void> _startSignalRConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        _logout();
        return;
      }

      final serverUrl = AppConfig.rideHubUrl;
      _hubConnection = HubConnectionBuilder()
          .withUrl(serverUrl, options: HttpConnectionOptions(
            accessTokenFactory: () async => token,
          ))
          .withAutomaticReconnect()
          .build();

      _hubConnection!.onreconnecting(({error}) {
        AppLogger.warn('SignalR', 'Driver reconnecting: $error');
        if (mounted) setState(() => _isConnected = false);
      });

      _hubConnection!.onreconnected(({connectionId}) {
        AppLogger.info('SignalR', 'Driver reconnected successfully: $connectionId');
        if (mounted) setState(() => _isConnected = true);
      });

      _hubConnection!.onclose(({error}) {
        AppLogger.error('SignalR', 'Driver connection closed', error);
        if (mounted) setState(() => _isConnected = false);
      });

      _hubConnection!.on("ReceiveRideRequest", _handleNewRideRequest);
      _hubConnection!.on("RideClaimSuccess", (args) {
        AppLogger.info('DriverMap', 'Ride claim acknowledged by server: $args');
      });
      _hubConnection!.on("RideError", (args) {
        final message = (args != null && args.isNotEmpty) ? args[0].toString() : 'An error occurred';
        AppLogger.warn('DriverMap', 'Server returned RideError: $message');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        }
      });

      await _hubConnection!.start();
      if (mounted) setState(() => _isConnected = true);
      AppLogger.info('DriverMap', 'Driver $_driverId connected to SignalR Hub');

      await _startLocationTracking();
    } catch (e, stack) {
      AppLogger.error('DriverMap', 'SignalR connect failed', e, stack);
      if (mounted) setState(() => _isConnected = false);
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable GPS / Location services.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position initialPosition = await Geolocator.getCurrentPosition();
      _updateLocationState(initialPosition);

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position? position) async {
        if (position != null) {
          _updateLocationState(position);

          if (_hubConnection?.state == HubConnectionState.Connected && _activeRideId != null) {
            try {
              await _hubConnection!.invoke("UpdateLocation", args: [
                _activeRideId!,
                position.latitude,
                position.longitude,
              ]);
            } catch (err) {
              AppLogger.error('DriverLocation', 'Failed pushing coordinates to hub', err);
            }
          }
        }
      });
    } catch (e, stack) {
      AppLogger.error('DriverLocation', 'Failed initializing location tracking', e, stack);
    }
  }

  void _updateLocationState(Position position) {
    final latLng = LatLng(position.latitude, position.longitude);
    final isFirst = _currentLocation == null;

    if (mounted) {
      setState(() => _currentLocation = latLng);
      if (!isFirst) {
        _mapController.move(latLng, 16.5);
      }
    }
  }

  void _handleNewRideRequest(List<Object?>? arguments) {
    if (arguments != null && arguments.length >= 3) {
      final int rideId = int.tryParse(arguments[0].toString()) ?? 0;
      final int riderId = int.tryParse(arguments[1].toString()) ?? 0;
      final String rideDetails = arguments[2].toString();

      AppLogger.info('DriverMap', 'Incoming dispatch offer: Ride #$rideId, Rider #$riderId');

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("🚖 NEW FARE DISPATCH"),
          content: Text(rideDetails),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("DECLINE", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _acceptRide(rideId, riderId);
              },
              child: const Text("ACCEPT", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _acceptRide(int rideId, int riderId) async {
    try {
      if (_hubConnection?.state == HubConnectionState.Connected) {
        await _hubConnection!.invoke("AcceptRide", args: [rideId, riderId]);
        if (mounted) {
          setState(() => _activeRideId = rideId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride Accepted! Tracking started.'), backgroundColor: Colors.green),
          );
        }
        AppLogger.info('DriverMap', 'Sent AcceptRide for Ride #$rideId');
      }
    } catch (e, stack) {
      AppLogger.error('DriverMap', 'Error invoking AcceptRide', e, stack);
    }
  }

  Future<void> _completeRide() async {
    if (_activeRideId == null) return;
    try {
      if (_hubConnection?.state == HubConnectionState.Connected) {
        await _hubConnection!.invoke("CompleteRide", args: [_activeRideId!]);
      }
      if (mounted) {
        setState(() => _activeRideId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride completed!'), backgroundColor: Colors.green),
        );
      }
      AppLogger.info('DriverMap', 'Ride completed successfully');
    } catch (e, stack) {
      AppLogger.error('DriverMap', 'Error invoking CompleteRide', e, stack);
    }
  }

  Future<void> _logout() async {
    try {
      await _positionStreamSubscription?.cancel();
      await _hubConnection?.stop();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      AppLogger.info('DriverMap', 'Driver logged out');
    } catch (e) {
      AppLogger.error('DriverMap', 'Error during logout', e);
    }

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _hubConnection?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Dispatch (ID: $_driverId)'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Stack(
        children: [
          _currentLocation == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation!,
                    initialZoom: 16.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.repid_ride_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentLocation!,
                          width: 50,
                          height: 50,
                          child: const Icon(Icons.directions_car, color: Colors.blue, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isConnected ? Icons.wifi : Icons.wifi_off,
                    color: _isConnected ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isConnected ? 'Connected to Live Dispatch' : 'Connecting to server...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_activeRideId != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: _completeRide,
                  child: const Text('COMPLETE RIDE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}