import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../config.dart';
import '../services/logger_service.dart';
import 'login_screen.dart';

class RiderMapScreen extends StatefulWidget {
  const RiderMapScreen({super.key});

  @override
  State<RiderMapScreen> createState() => _RiderMapScreenState();
}

class _RiderMapScreenState extends State<RiderMapScreen> {
  HubConnection? _hubConnection;
  bool _isConnected = false;
  bool _isRideRequested = false;
  int? _activeRideId;

  final MapController _mapController = MapController();
  LatLng? _riderLocation;
  LatLng? _driverLocation;

  @override
  void initState() {
    super.initState();
    _initRiderScreen();
  }

  Future<void> _initRiderScreen() async {
    await _acquireRiderLocation();
    await _startSignalRConnection();
  }

  Future<void> _acquireRiderLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable GPS / Location services.')),
          );
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final loc = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _riderLocation = loc;
        });
        _mapController.move(loc, 15.0);
      }
      AppLogger.info('RiderMap', 'Rider GPS acquired at (${posToString(loc)})');
    } catch (e, stack) {
      AppLogger.warn('RiderMap', 'Could not get real GPS, using default city center: $e\n$stack');
      if (mounted && _riderLocation == null) {
        setState(() {
          _riderLocation = const LatLng(30.900965, 75.857275);
        });
      }
    }
  }

  String posToString(LatLng pos) => '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';

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
        AppLogger.warn('RiderSignalR', 'Reconnecting: $error');
        if (mounted) setState(() => _isConnected = false);
      });

      _hubConnection!.onreconnected(({connectionId}) {
        AppLogger.info('RiderSignalR', 'Reconnected successfully: $connectionId');
        if (mounted) setState(() => _isConnected = true);
      });

      _hubConnection!.onclose(({error}) {
        AppLogger.error('RiderSignalR', 'Connection closed', error);
        if (mounted) setState(() => _isConnected = false);
      });

      _hubConnection!.on("ReceiveLocationUpdate", _handleDriverLocationUpdate);
      _hubConnection!.on("RideAccepted", _handleRideAccepted);
      _hubConnection!.on("RideCompleted", _handleRideCompleted);
      _hubConnection!.on("RideError", (args) {
        final err = (args != null && args.isNotEmpty) ? args[0].toString() : 'Ride request error';
        AppLogger.warn('RiderMap', 'Server sent RideError: $err');
        if (mounted) {
          setState(() => _isRideRequested = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: Colors.red),
          );
        }
      });

      await _hubConnection!.start();
      if (mounted) setState(() => _isConnected = true);
      AppLogger.info('RiderMap', 'Rider connected to SignalR Hub');
    } catch (e, stack) {
      AppLogger.error('RiderMap', 'Failed starting SignalR', e, stack);
      if (mounted) setState(() => _isConnected = false);
    }
  }

  Future<void> _handleRideAccepted(List<Object?>? arguments) async {
    if (arguments != null && arguments.length >= 2) {
      final rideId = int.tryParse(arguments[0].toString()) ?? 0;
      final driverId = arguments[1].toString();

      _activeRideId = rideId;
      AppLogger.info('RiderMap', 'Ride #$rideId accepted by Driver #$driverId. Joining tracking room.');

      try {
        await _hubConnection?.invoke("JoinRideGroup", args: [rideId]);
      } catch (err) {
        AppLogger.error('RiderMap', 'Failed to join active ride room', err);
      }

      if (mounted) {
        setState(() {}); // refresh title with active ride ID
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver #$driverId accepted! Vehicle is on the way.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _handleRideCompleted(List<Object?>? arguments) {
    AppLogger.info('RiderMap', 'Ride completed signal received');
    if (mounted) {
      setState(() {
        _isRideRequested = false;
        _driverLocation = null;
        _activeRideId = null;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("🏁 Destination Reached!"),
          content: const Text("Your ride has successfully completed. Thank you for using Rapid Ride!"),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK", style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      );
    }
  }

  void _handleDriverLocationUpdate(List<Object?>? arguments) {
    if (arguments != null && arguments.length >= 2) {
      final lat = double.tryParse(arguments[0].toString());
      final lng = double.tryParse(arguments[1].toString());

      if (lat != null && lng != null) {
        final newLocation = LatLng(lat, lng);
        if (mounted) {
          setState(() {
            _driverLocation = newLocation;
          });
          _mapController.move(newLocation, 16.0);
        }
      }
    }
  }

  Future<void> _requestRide() async {
    if (_riderLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acquiring your location... Please wait.')),
      );
      await _acquireRiderLocation();
      return;
    }

    try {
      if (_hubConnection?.state == HubConnectionState.Connected) {
        setState(() {
          _isRideRequested = true;
        });

        AppLogger.info('RiderMap', 'Broadcasting ride request at (${posToString(_riderLocation!)})');
        await _hubConnection!.invoke("RequestRide", args: [
          _riderLocation!.latitude,
          _riderLocation!.longitude,
        ]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request broadcasted! Waiting for a nearby driver...'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not connected to dispatch. Retrying connection...')),
          );
        }
        await _startSignalRConnection();
      }
    } catch (e, stack) {
      AppLogger.error('RiderMap', 'Error invoking RequestRide', e, stack);
      if (mounted) {
        setState(() => _isRideRequested = false);
      }
    }
  }

  Future<void> _logout() async {
    try {
      await _hubConnection?.stop();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      AppLogger.info('RiderMap', 'Rider logged out');
    } catch (e) {
      AppLogger.error('RiderMap', 'Logout error', e);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _hubConnection?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _riderLocation ?? const LatLng(30.900965, 75.857275);

    return Scaffold(
      appBar: AppBar(
        title: Text(_activeRideId != null ? 'Rapid Ride (Ride #$_activeRideId)' : 'Rapid Ride'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.repid_ride_app',
              ),
              MarkerLayer(
                markers: [
                  if (_riderLocation != null)
                    Marker(
                      point: _riderLocation!,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.person_pin_circle, color: Colors.green, size: 42),
                    ),
                  if (_driverLocation != null)
                    Marker(
                      point: _driverLocation!,
                      width: 44,
                      height: 44,
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
                    _isConnected ? 'Connected to Network' : 'Connecting...',
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
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRideRequested ? Colors.grey : Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _isRideRequested ? null : _requestRide,
                child: Text(
                  _isRideRequested ? 'FINDING DRIVER...' : 'REQUEST RIDE',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}