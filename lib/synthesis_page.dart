import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sophia_transcrit2/documents_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:isolate';

import 'home.dart';
import 'requests_manager.dart';
import 'file_manager_s.dart';
import 'notification_service.dart';


class SynthesisPage extends StatefulWidget {
  final String folder;
  final List<String> pathList;
  const SynthesisPage({super.key, required this.folder, required this.pathList});

  @override
  State<SynthesisPage> createState() => _SynthesisPage();
}

class _SynthesisPage extends State<SynthesisPage> {

  late String folder;
  late List<String> pathList;
  late int counter;
  late AppProvider _appProvider;
  late final NotificationService notificationService;
  final ReceivePort _port = ReceivePort();
  late TextEditingController myController;

  Future<void> computeFuture = Future.value();
  List<String> reqList = [];
  String documentFolder = "documents";
  String newReq = "";
  bool keySelected = false;
  bool sumSelected = true;

  @override
  void initState() {
    getSharedPref();
    notificationService = NotificationService();
    listenToNotificationStream();
    notificationService.initializePlatformNotifications();

    super.initState();
    folder = widget
        .folder;
    pathList = widget
        .pathList;
    _appProvider = Provider.of<AppProvider>(context, listen: false);
    myController = TextEditingController();

    reqList = ['Dame las palabras clave del texto', 'Dame el resumen del texto.'];
  }

  void listenToNotificationStream() =>
      notificationService.behaviorSubject.listen((payload) {
        _appProvider.setScreen(const DocumentsPage(), 2);
      });

  void getSharedPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      counter = (prefs.getInt('counter') ?? 0);
    });
  }

  void _incrementCounter() async {
    final prefs = await SharedPreferences.getInstance();
    final c = (prefs.getInt('counter') ?? 0)+1;
    counter = c;
    prefs.setInt('counter', counter);
  }

  @override
  void dispose() {
    // Clean up the controller when the widget is disposed.
    myController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        margin: const EdgeInsets.fromLTRB(15, 40, 15, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
                children: [
                  IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back, size: 35)
                  ),
                ]
            ),
            const Center(
              child: Text(
                  "What's next?",
                  style: TextStyle(fontSize: 30)
              ),
            ),
            const Center(
              child: Text(
                  'Generate your document.',
                  style: TextStyle(fontSize: 17)
              ),
            ),
            const SizedBox(height: 50),
            /*Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                      "Key words",
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 30),
                  Switch(
                    value: keySelected,
                    onChanged: (value) {
                      setState(() {
                        keySelected = value;
                      });
                    },
                  ),
                ]
            ),
            const SizedBox(height: 20),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                      "Summary",
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 30),
                  Switch(
                    value: sumSelected,
                    onChanged: (value) {
                      setState(() {
                        sumSelected = value;
                      });
                    },
                  ),
                ]
            ),*/
            FloatingActionButton.extended(
              onPressed: () async {
                final req = await openDialog();
                if (req == null || req.isEmpty) return;
                setState(() { reqList.add(req); });
              },
              label: const Text('New request'),
              icon: const Icon(Icons.add),
            ),
            SizedBox(
              height: 400,
              child: ListView.builder(
                itemCount: reqList.length,
                scrollDirection: Axis.vertical,
                itemBuilder: (context, index) {
                  return Card(
                      child: ListTile(
                        title: Text(reqList[index]),
                        trailing: IconButton(
                          icon: const Icon(Icons.highlight_remove),
                          onPressed: () => setState(() { reqList.removeAt(index); }),
                        ),
                      )
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if(sumSelected || keySelected){
                  _startBackgroundTask();
                  Navigator.pop(context);
                  _appProvider.setScreen(const DocumentsPage(), 2);
                }
              },
              child: const Text('Done')
            )
          ],
        ),
      ),
    );
  }

  Future<String?> openDialog() => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New Request'),
      content: TextField(
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Enter a new request'
        ),
        controller: myController
      ),
      actions: [
        TextButton(
          onPressed: submitRequest,
          child: const Text('SUBMIT'),
        )
      ]
    ),
  );

  void submitRequest(){
    Navigator.of(context).pop(myController.text);
    myController.clear();
  }

  void _startBackgroundTask() async {
    await Isolate.spawn(_backgroundTask, [_port.sendPort, folder, pathList, keySelected, sumSelected]);
    _port.listen((message) {
      // Handle background task completion
      writeDocument('documents', 'document$counter', message);
      _appProvider.addDocument('document$counter.txt');

      // Save an integer value to 'counter' key.
      _incrementCounter();

      notificationService.showLocalNotification(
          id: 0,
          title: "Your document is ready!",
          body: "Tap to continue.",
          payload: ""
      );
    });
    notificationService.showLocalNotification(
        id: 0,
        title: "Text processing in progress...",
        body: "",
        payload: ""
    );
  }

  static void _backgroundTask(List<dynamic> args) {
    SendPort sendPort = args[0];
    String folder = args[1];
    List<String> pathList = args[2];
    bool keySelected = args[3];
    bool sumSelected = args[4];

    () async {
      for (var file in pathList){
        await sendText('$folder/$file');
      }
      var content = await getProcessedContent(pathList, keySelected, sumSelected);

      sendPort.send(content);
    }();
  }
}