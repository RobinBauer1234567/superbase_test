// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:premier_league/data_service.dart';

class SpieltageScreen extends StatefulWidget {
  @override
  _SpieltageScreenState createState() => _SpieltageScreenState();
}

class _SpieltageScreenState extends State<SpieltageScreen> {
  List<dynamic> spieltage = [];
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchSpieltage();
  }

  Future<void> fetchSpieltage() async {
    setState(() {
      _isLoading = true;
    });
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final response = await dataManagement.supabaseService.supabase
        .from('spieltag')
        .select()
        .eq('season_id', dataManagement.seasonId)
        .order('round', ascending: true);

    if (mounted) {
      setState(() {
        spieltage = response;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltage')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spieltage.length,
        itemBuilder: (context, index) {
          final spieltag = spieltage[index];
          return ListTile(
            title: Text("Spieltag ${spieltag['round']}"),
            subtitle: Text("Status: ${spieltag['status']}"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HomeScreen(round: spieltag['round']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}