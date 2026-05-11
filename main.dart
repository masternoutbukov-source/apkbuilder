
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  runApp(const MetalEstimatorApp());
}

class MetalEstimatorApp extends StatelessWidget {
  const MetalEstimatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'МеталлСмета 48',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final EstimatorModel model;
  int index = 0;
  bool isBusy = false;

  @override
  void initState() {
    super.initState();
    model = EstimatorModel();
  }

  Future<void> _runAction(
    Future<File> Function() action,
    String successLabel,
  ) async {
    setState(() => isBusy = true);
    try {
      final file = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel\n${file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => isBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FencePage(model: model),
      GaragePage(model: model),
      SheetPage(model: model),
      SuppliersPage(model: model),
      SummaryPage(
        model: model,
        onSaveJson: () => _runAction(
          model.saveProjectJson,
          'Проект сохранен в JSON',
        ),
        onRestoreJson: () async {
          setState(() => isBusy = true);
          try {
            final file = await model.restoreLatestProjectJson();
            if (!mounted) return;
            final label = file == null
                ? 'Сохраненный JSON пока не найден'
                : 'Проект восстановлен из JSON\n${file.path}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(label)),
            );
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка: $error')),
            );
          } finally {
            if (mounted) {
              setState(() => isBusy = false);
            }
          }
        },
        onExportPdf: () => _runAction(
          model.exportEstimatePdf,
          'PDF смета сохранена',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(model.projectName),
        centerTitle: false,
        actions: [
          if (isBusy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fence_outlined),
            selectedIcon: Icon(Icons.fence),
            label: 'Забор',
          ),
          NavigationDestination(
            icon: Icon(Icons.garage_outlined),
            selectedIcon: Icon(Icons.garage),
            label: 'Гараж',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Лист',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Поставщики',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Итог',
          ),
        ],
      ),
    );
  }
}

enum RoofKind { singleSlope, gable }
enum SheetKind { hotRolled, coldRolled, galvanized }
enum CutAngle { straight, miter45 }

class PipeProfile {
  const PipeProfile({
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.thicknessMm,
    required this.weightPerMeterKg,
    required this.defaultPricePerMeter,
  });

  final String name;
  final double widthMm;
  final double heightMm;
  final double thicknessMm;
  final double weightPerMeterKg;
  final double defaultPricePerMeter;
}

class ProfSheetProfile {
  const ProfSheetProfile({
    required this.name,
    required this.usefulWidthM,
    required this.fullWidthM,
    required this.defaultPricePerSqm,
  });

  final String name;
  final double usefulWidthM;
  final double fullWidthM;
  final double defaultPricePerSqm;
}

class SupplierCatalog {
  const SupplierCatalog({
    required this.name,
    required this.site,
    required this.notes,
    required this.pipePrices,
    required this.profSheetPrices,
    required this.sheetPrices,
  });

  final String name;
  final String site;
  final String notes;
  final Map<String, double> pipePrices;
  final Map<String, double> profSheetPrices;
  final Map<SheetKind, double> sheetPrices;
}

class PipePiece {
  const PipePiece({
    required this.group,
    required this.label,
    required this.lengthM,
    required this.quantity,
    this.startAngle = CutAngle.straight,
    this.endAngle = CutAngle.straight,
  });

  final String group;
  final String label;
  final double lengthM;
  final int quantity;
  final CutAngle startAngle;
  final CutAngle endAngle;

  double get totalLengthM => lengthM * quantity;

  int get totalMiterCuts {
    var perPiece = 0;
    if (startAngle == CutAngle.miter45) perPiece++;
    if (endAngle == CutAngle.miter45) perPiece++;
    return perPiece * quantity;
  }
}

class PipeCutUnit {
  const PipeCutUnit({
    required this.group,
    required this.label,
    required this.lengthM,
    required this.startAngle,
    required this.endAngle,
  });

  final String group;
  final String label;
  final double lengthM;
  final CutAngle startAngle;
  final CutAngle endAngle;
}

class StockBar {
  const StockBar({
    required this.index,
    required this.stockLengthM,
    required this.usedLengthM,
    required this.items,
  });

  final int index;
  final double stockLengthM;
  final double usedLengthM;
  final List<PipeCutUnit> items;

  double get wasteLengthM => math.max(0, stockLengthM - usedLengthM);
}

class SheetCutPiece {
  const SheetCutPiece({
    required this.group,
    required this.coverWidthM,
    required this.actualWidthM,
    required this.heightM,
    this.quantity = 1,
  });

  final String group;
  final double coverWidthM;
  final double actualWidthM;
  final double heightM;
  final int quantity;

  double get purchasedAreaSqm => actualWidthM * heightM * quantity;
}

class FenceCutPlan {
  const FenceCutPlan({
    required this.sheetPieces,
    required this.pipePieces,
    required this.stockBars,
    required this.exactSheetAreaSqm,
    required this.purchasedSheetAreaSqm,
    required this.stripCount,
    required this.miter45Cuts,
  });

  final List<SheetCutPiece> sheetPieces;
  final List<PipePiece> pipePieces;
  final List<StockBar> stockBars;
  final double exactSheetAreaSqm;
  final double purchasedSheetAreaSqm;
  final int stripCount;
  final int miter45Cuts;
}

class GarageCutPlan {
  const GarageCutPlan({
    required this.wallPieces,
    required this.roofPieces,
    required this.pipePieces,
    required this.stockBars,
    required this.wallExactAreaSqm,
    required this.wallPurchasedAreaSqm,
    required this.roofExactAreaSqm,
    required this.roofPurchasedAreaSqm,
    required this.wallStripCount,
    required this.roofStripCount,
    required this.miter45Cuts,
  });

  final List<SheetCutPiece> wallPieces;
  final List<SheetCutPiece> roofPieces;
  final List<PipePiece> pipePieces;
  final List<StockBar> stockBars;
  final double wallExactAreaSqm;
  final double wallPurchasedAreaSqm;
  final double roofExactAreaSqm;
  final double roofPurchasedAreaSqm;
  final int wallStripCount;
  final int roofStripCount;
  final int miter45Cuts;
}

class FenceResult {
  const FenceResult({
    required this.exactPipeLengthM,
    required this.commercialPipeLengthM,
    required this.pipeWeightKg,
    required this.postsCount,
    required this.railRows,
    required this.fastenersCount,
    required this.concreteVolumeM3,
    required this.pipeCost,
    required this.sheetCost,
    required this.fastenersCost,
    required this.concreteCost,
    required this.totalCost,
    required this.whips6m,
    required this.cutPlan,
  });

  final double exactPipeLengthM;
  final double commercialPipeLengthM;
  final double pipeWeightKg;
  final int postsCount;
  final int railRows;
  final int fastenersCount;
  final double concreteVolumeM3;
  final double pipeCost;
  final double sheetCost;
  final double fastenersCost;
  final double concreteCost;
  final double totalCost;
  final int whips6m;
  final FenceCutPlan cutPlan;
}

class GarageResult {
  const GarageResult({
    required this.exactPipeLengthM,
    required this.commercialPipeLengthM,
    required this.pipeWeightKg,
    required this.wallPostsCount,
    required this.fastenersCount,
    required this.pipeCost,
    required this.wallSheetCost,
    required this.roofSheetCost,
    required this.fastenersCost,
    required this.totalCost,
    required this.whips6m,
    required this.cutPlan,
  });

  final double exactPipeLengthM;
  final double commercialPipeLengthM;
  final double pipeWeightKg;
  final int wallPostsCount;
  final int fastenersCount;
  final double pipeCost;
  final double wallSheetCost;
  final double roofSheetCost;
  final double fastenersCost;
  final double totalCost;
  final int whips6m;
  final GarageCutPlan cutPlan;
}

class SheetMetalResult {
  const SheetMetalResult({
    required this.totalAreaSqm,
    required this.totalWeightKg,
    required this.totalCost,
  });

  final double totalAreaSqm;
  final double totalWeightKg;
  final double totalCost;
}

class ProjectSummaryResult {
  const ProjectSummaryResult({
    required this.pipeLengthM,
    required this.pipeWeightKg,
    required this.profSheetPurchasedAreaSqm,
    required this.profSheetCount,
    required this.extraSheetAreaSqm,
    required this.materialCost,
    required this.overheadsCost,
    required this.totalCost,
  });

  final double pipeLengthM;
  final double pipeWeightKg;
  final double profSheetPurchasedAreaSqm;
  final int profSheetCount;
  final double extraSheetAreaSqm;
  final double materialCost;
  final double overheadsCost;
  final double totalCost;
}

class EstimatorModel extends ChangeNotifier {
  final List<PipeProfile> pipeProfiles = const [
    PipeProfile(
      name: '20×20×2',
      widthMm: 20,
      heightMm: 20,
      thicknessMm: 2,
      weightPerMeterKg: 1.12,
      defaultPricePerMeter: 118,
    ),
    PipeProfile(
      name: '40×20×2',
      widthMm: 40,
      heightMm: 20,
      thicknessMm: 2,
      weightPerMeterKg: 1.70,
      defaultPricePerMeter: 165,
    ),
    PipeProfile(
      name: '40×40×2',
      widthMm: 40,
      heightMm: 40,
      thicknessMm: 2,
      weightPerMeterKg: 2.38,
      defaultPricePerMeter: 220,
    ),
    PipeProfile(
      name: '60×40×2',
      widthMm: 60,
      heightMm: 40,
      thicknessMm: 2,
      weightPerMeterKg: 2.98,
      defaultPricePerMeter: 285,
    ),
    PipeProfile(
      name: '80×80×3',
      widthMm: 80,
      heightMm: 80,
      thicknessMm: 3,
      weightPerMeterKg: 7.10,
      defaultPricePerMeter: 560,
    ),
  ];

  final List<ProfSheetProfile> profSheets = const [
    ProfSheetProfile(
      name: 'Профнастил C8',
      usefulWidthM: 1.15,
      fullWidthM: 1.20,
      defaultPricePerSqm: 690,
    ),
    ProfSheetProfile(
      name: 'Профнастил C20',
      usefulWidthM: 1.10,
      fullWidthM: 1.15,
      defaultPricePerSqm: 780,
    ),
    ProfSheetProfile(
      name: 'Профнастил HC35',
      usefulWidthM: 1.00,
      fullWidthM: 1.06,
      defaultPricePerSqm: 960,
    ),
  ];

  final List<SupplierCatalog> suppliers = const [
    SupplierCatalog(
      name: 'Труба48',
      site: 'truba48.ru',
      notes: 'Профильные трубы, лист, профнастил, доставка по области.',
      pipePrices: {
        '20×20×2': 116,
        '40×20×2': 162,
        '40×40×2': 218,
        '60×40×2': 282,
        '80×80×3': 555,
      },
      profSheetPrices: {
        'Профнастил C8': 685,
        'Профнастил C20': 775,
        'Профнастил HC35': 955,
      },
      sheetPrices: {
        SheetKind.hotRolled: 3450,
        SheetKind.coldRolled: 3890,
        SheetKind.galvanized: 4620,
      },
    ),
    SupplierCatalog(
      name: 'ПОЛАНДР',
      site: 'polandr.ru',
      notes: 'Металлопрокат, оцинковка, профлист, прайс-листы.',
      pipePrices: {
        '20×20×2': 120,
        '40×20×2': 167,
        '40×40×2': 224,
        '60×40×2': 289,
        '80×80×3': 568,
      },
      profSheetPrices: {
        'Профнастил C8': 705,
        'Профнастил C20': 790,
        'Профнастил HC35': 975,
      },
      sheetPrices: {
        SheetKind.hotRolled: 3520,
        SheetKind.coldRolled: 3950,
        SheetKind.galvanized: 4710,
      },
    ),
    SupplierCatalog(
      name: 'НЛТЗ / NLTZshop',
      site: 'nltz.ru',
      notes: 'Трубный и листовой прокат, резка, гибка, доставка.',
      pipePrices: {
        '20×20×2': 122,
        '40×20×2': 171,
        '40×40×2': 228,
        '60×40×2': 292,
        '80×80×3': 575,
      },
      profSheetPrices: {
        'Профнастил C8': 710,
        'Профнастил C20': 798,
        'Профнастил HC35': 985,
      },
      sheetPrices: {
        SheetKind.hotRolled: 3560,
        SheetKind.coldRolled: 3980,
        SheetKind.galvanized: 4760,
      },
    ),
    SupplierCatalog(
      name: 'Металлоторг Липецк',
      site: 'metallotorg.ru',
      notes: 'База металлопроката в Липецке, прайс по профилям.',
      pipePrices: {
        '20×20×2': 119,
        '40×20×2': 166,
        '40×40×2': 222,
        '60×40×2': 287,
        '80×80×3': 562,
      },
      profSheetPrices: {
        'Профнастил C8': 700,
        'Профнастил C20': 788,
        'Профнастил HC35': 972,
      },
      sheetPrices: {
        SheetKind.hotRolled: 3500,
        SheetKind.coldRolled: 3920,
        SheetKind.galvanized: 4680,
      },
    ),
  ];

  String projectName = 'МеталлСмета 48';
  int selectedSupplierIndex = 0;
  int selectedPipeIndex = 2;
  int selectedProfSheetIndex = 1;

  bool useSupplierPrices = true;
  double manualPipePricePerM = 220;
  double manualProfSheetPricePerSqm = 780;
  double manualSheetPricePerPiece = 3950;

  bool includeFence = true;
  double fenceLengthM = 30;
  double fenceHeightM = 2;
  double fencePostStepM = 2.5;
  double fencePostEmbedM = 1.2;
  bool fenceHasGate = true;
  double fenceGateWidthM = 4;
  bool fenceGateCladded = true;
  bool fenceHasWicket = true;
  double fenceWicketWidthM = 1;
  bool fenceWicketCladded = true;
  double fenceWastePercent = 5;

  bool includeGarage = false;
  double garageLengthM = 6;
  double garageWidthM = 4;
  double garageHeightM = 2.5;
  double garageFrameStepM = 2.0;
  double garageRoofOverhangM = 0.2;
  double garageRoofSlopeDeg = 18;
  RoofKind garageRoofKind = RoofKind.singleSlope;
  double garageGateWidthM = 3;
  double garageGateHeightM = 2.4;
  double garageWastePercent = 6;

  bool includeSheet = false;
  SheetKind sheetKind = SheetKind.hotRolled;
  double sheetLengthM = 2.5;
  double sheetWidthM = 1.25;
  double sheetThicknessMm = 2.0;
  int sheetCount = 1;

  double deliveryCost = 0;
  double weldingCost = 0;
  double paintCost = 0;
  double mountingCost = 0;
  double fastenerPrice = 3.8;
  double concretePricePerM3 = 5200;
  double stockLengthM = 6;
  double sawKerfMm = 3;

  String? lastSavedJsonPath;
  String? lastSavedPdfPath;

  SupplierCatalog get supplier => suppliers[selectedSupplierIndex];
  PipeProfile get pipe => pipeProfiles[selectedPipeIndex];
  ProfSheetProfile get profSheet => profSheets[selectedProfSheetIndex];

  double get pipePricePerM {
    if (!useSupplierPrices) return manualPipePricePerM;
    return supplier.pipePrices[pipe.name] ?? pipe.defaultPricePerMeter;
  }

  double get profSheetPricePerSqm {
    if (!useSupplierPrices) return manualProfSheetPricePerSqm;
    return supplier.profSheetPrices[profSheet.name] ?? profSheet.defaultPricePerSqm;
  }

  double get sheetPricePerPiece {
    if (!useSupplierPrices) return manualSheetPricePerPiece;
    return supplier.sheetPrices[sheetKind] ?? manualSheetPricePerPiece;
  }

  FenceResult get fenceResult => CalculationService.fence(this);
  GarageResult get garageResult => CalculationService.garage(this);
  SheetMetalResult get sheetResult => CalculationService.sheetMetal(this);
  ProjectSummaryResult get summary => CalculationService.summary(this);

  void setSupplierIndex(int value) {
    selectedSupplierIndex = value;
    notifyListeners();
  }

  void setPipeIndex(int value) {
    selectedPipeIndex = value;
    notifyListeners();
  }

  void setProfSheetIndex(int value) {
    selectedProfSheetIndex = value;
    notifyListeners();
  }

  void setUseSupplierPrices(bool value) {
    useSupplierPrices = value;
    notifyListeners();
  }

  void setRoofKind(RoofKind value) {
    garageRoofKind = value;
    notifyListeners();
  }

  void setSheetKind(SheetKind value) {
    sheetKind = value;
    notifyListeners();
  }

  void notify() => notifyListeners();

  Map<String, dynamic> toJsonMap() {
    return {
      'projectName': projectName,
      'selectedSupplierIndex': selectedSupplierIndex,
      'selectedPipeIndex': selectedPipeIndex,
      'selectedProfSheetIndex': selectedProfSheetIndex,
      'useSupplierPrices': useSupplierPrices,
      'manualPipePricePerM': manualPipePricePerM,
      'manualProfSheetPricePerSqm': manualProfSheetPricePerSqm,
      'manualSheetPricePerPiece': manualSheetPricePerPiece,
      'includeFence': includeFence,
      'fenceLengthM': fenceLengthM,
      'fenceHeightM': fenceHeightM,
      'fencePostStepM': fencePostStepM,
      'fencePostEmbedM': fencePostEmbedM,
      'fenceHasGate': fenceHasGate,
      'fenceGateWidthM': fenceGateWidthM,
      'fenceGateCladded': fenceGateCladded,
      'fenceHasWicket': fenceHasWicket,
      'fenceWicketWidthM': fenceWicketWidthM,
      'fenceWicketCladded': fenceWicketCladded,
      'fenceWastePercent': fenceWastePercent,
      'includeGarage': includeGarage,
      'garageLengthM': garageLengthM,
      'garageWidthM': garageWidthM,
      'garageHeightM': garageHeightM,
      'garageFrameStepM': garageFrameStepM,
      'garageRoofOverhangM': garageRoofOverhangM,
      'garageRoofSlopeDeg': garageRoofSlopeDeg,
      'garageRoofKind': garageRoofKind.name,
      'garageGateWidthM': garageGateWidthM,
      'garageGateHeightM': garageGateHeightM,
      'garageWastePercent': garageWastePercent,
      'includeSheet': includeSheet,
      'sheetKind': sheetKind.name,
      'sheetLengthM': sheetLengthM,
      'sheetWidthM': sheetWidthM,
      'sheetThicknessMm': sheetThicknessMm,
      'sheetCount': sheetCount,
      'deliveryCost': deliveryCost,
      'weldingCost': weldingCost,
      'paintCost': paintCost,
      'mountingCost': mountingCost,
      'fastenerPrice': fastenerPrice,
      'concretePricePerM3': concretePricePerM3,
      'stockLengthM': stockLengthM,
      'sawKerfMm': sawKerfMm,
      'savedAt': DateTime.now().toIso8601String(),
    };
  }

  void loadFromJsonMap(Map<String, dynamic> map) {
    projectName = _stringValue(map['projectName'], projectName);
    selectedSupplierIndex = _boundedIntValue(
      map['selectedSupplierIndex'],
      selectedSupplierIndex,
      maxValue: suppliers.length - 1,
    );
    selectedPipeIndex = _boundedIntValue(
      map['selectedPipeIndex'],
      selectedPipeIndex,
      maxValue: pipeProfiles.length - 1,
    );
    selectedProfSheetIndex = _boundedIntValue(
      map['selectedProfSheetIndex'],
      selectedProfSheetIndex,
      maxValue: profSheets.length - 1,
    );
    useSupplierPrices = _boolValue(map['useSupplierPrices'], useSupplierPrices);
    manualPipePricePerM = _doubleValue(map['manualPipePricePerM'], manualPipePricePerM);
    manualProfSheetPricePerSqm = _doubleValue(
      map['manualProfSheetPricePerSqm'],
      manualProfSheetPricePerSqm,
    );
    manualSheetPricePerPiece = _doubleValue(
      map['manualSheetPricePerPiece'],
      manualSheetPricePerPiece,
    );

    includeFence = _boolValue(map['includeFence'], includeFence);
    fenceLengthM = _doubleValue(map['fenceLengthM'], fenceLengthM);
    fenceHeightM = _doubleValue(map['fenceHeightM'], fenceHeightM);
    fencePostStepM = _doubleValue(map['fencePostStepM'], fencePostStepM);
    fencePostEmbedM = _doubleValue(map['fencePostEmbedM'], fencePostEmbedM);
    fenceHasGate = _boolValue(map['fenceHasGate'], fenceHasGate);
    fenceGateWidthM = _doubleValue(map['fenceGateWidthM'], fenceGateWidthM);
    fenceGateCladded = _boolValue(map['fenceGateCladded'], fenceGateCladded);
    fenceHasWicket = _boolValue(map['fenceHasWicket'], fenceHasWicket);
    fenceWicketWidthM = _doubleValue(map['fenceWicketWidthM'], fenceWicketWidthM);
    fenceWicketCladded = _boolValue(map['fenceWicketCladded'], fenceWicketCladded);
    fenceWastePercent = _doubleValue(map['fenceWastePercent'], fenceWastePercent);

    includeGarage = _boolValue(map['includeGarage'], includeGarage);
    garageLengthM = _doubleValue(map['garageLengthM'], garageLengthM);
    garageWidthM = _doubleValue(map['garageWidthM'], garageWidthM);
    garageHeightM = _doubleValue(map['garageHeightM'], garageHeightM);
    garageFrameStepM = _doubleValue(map['garageFrameStepM'], garageFrameStepM);
    garageRoofOverhangM = _doubleValue(map['garageRoofOverhangM'], garageRoofOverhangM);
    garageRoofSlopeDeg = _doubleValue(map['garageRoofSlopeDeg'], garageRoofSlopeDeg);
    garageRoofKind = _roofKindValue(map['garageRoofKind'], garageRoofKind);
    garageGateWidthM = _doubleValue(map['garageGateWidthM'], garageGateWidthM);
    garageGateHeightM = _doubleValue(map['garageGateHeightM'], garageGateHeightM);
    garageWastePercent = _doubleValue(map['garageWastePercent'], garageWastePercent);

    includeSheet = _boolValue(map['includeSheet'], includeSheet);
    sheetKind = _sheetKindValue(map['sheetKind'], sheetKind);
    sheetLengthM = _doubleValue(map['sheetLengthM'], sheetLengthM);
    sheetWidthM = _doubleValue(map['sheetWidthM'], sheetWidthM);
    sheetThicknessMm = _doubleValue(map['sheetThicknessMm'], sheetThicknessMm);
    sheetCount = _intValue(map['sheetCount'], sheetCount);

    deliveryCost = _doubleValue(map['deliveryCost'], deliveryCost);
    weldingCost = _doubleValue(map['weldingCost'], weldingCost);
    paintCost = _doubleValue(map['paintCost'], paintCost);
    mountingCost = _doubleValue(map['mountingCost'], mountingCost);
    fastenerPrice = _doubleValue(map['fastenerPrice'], fastenerPrice);
    concretePricePerM3 = _doubleValue(map['concretePricePerM3'], concretePricePerM3);
    stockLengthM = _doubleValue(map['stockLengthM'], stockLengthM);
    sawKerfMm = _doubleValue(map['sawKerfMm'], sawKerfMm);
    notifyListeners();
  }

  Future<Directory> _documentsDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> saveProjectJson() async {
    final directory = await _documentsDir();
    final timestamp = _timestampForFile();
    final latest = File('${directory.path}/project_latest.json');
    final archive = File('${directory.path}/project_$timestamp.json');
    final payload = const JsonEncoder.withIndent('  ').convert(toJsonMap());
    await archive.writeAsString(payload);
    await latest.writeAsString(payload);
    lastSavedJsonPath = archive.path;
    notifyListeners();
    return archive;
  }

  Future<File?> restoreLatestProjectJson() async {
    final directory = await _documentsDir();
    final latest = File('${directory.path}/project_latest.json');
    if (!await latest.exists()) {
      return null;
    }
    final raw = await latest.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON проекта поврежден');
    }
    loadFromJsonMap(decoded);
    lastSavedJsonPath = latest.path;
    notifyListeners();
    return latest;
  }

  Future<File> exportEstimatePdf() async {
    final directory = await _documentsDir();
    final timestamp = _timestampForFile();
    final file = File('${directory.path}/estimate_$timestamp.pdf');
    final summaryResult = summary;
    final fence = fenceResult;
    final garage = garageResult;
    final sheet = sheetResult;

    final pdf = pw.Document();
    final base = pw.TextStyle(font: pw.Font.helvetica(), fontSize: 10);
    final bold = pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 10);
    final big = pw.TextStyle(font: pw.Font.helveticaBold(), fontSize: 16);

    List<pw.TableRow> buildKeyValueRows(List<List<String>> rows) {
      return [
        for (final row in rows)
          pw.TableRow(
            children: [
              _pdfCell(row[0], base),
              _pdfCell(row[1], base),
            ],
          ),
      ];
    }

    List<pw.TableRow> buildSheetRows(List<SheetCutPiece> pieces) {
      final grouped = aggregateSheetPieces(pieces);
      return [
        pw.TableRow(
          children: [
            _pdfCell('Group', bold),
            _pdfCell('Qty', bold),
            _pdfCell('Cut width, m', bold),
            _pdfCell('Length, m', bold),
          ],
        ),
        for (final item in grouped)
          pw.TableRow(
            children: [
              _pdfCell(item.group, base),
              _pdfCell('${item.quantity}', base),
              _pdfCell(formatNumber(item.actualWidthM), base),
              _pdfCell(formatNumber(item.heightM), base),
            ],
          ),
      ];
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            pw.Text('Metal estimate', style: big),
            pw.SizedBox(height: 6),
            pw.Text('Project: ${_asciiSafe(projectName.isEmpty ? "Project" : projectName)}', style: base),
            pw.Text('Supplier: ${_asciiSafe(supplier.name)}', style: base),
            pw.Text('Date: ${DateTime.now().toIso8601String().substring(0, 10)}', style: base),
            pw.SizedBox(height: 18),
            pw.Text('Summary', style: bold),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
              },
              children: buildKeyValueRows([
                ['Pipe, commercial length', '${formatNumber(summaryResult.pipeLengthM)} m'],
                ['Pipe weight', '${formatNumber(summaryResult.pipeWeightKg)} kg'],
                ['Profile sheet purchased area', '${formatNumber(summaryResult.profSheetPurchasedAreaSqm)} m2'],
                ['Profile sheet strips', '${summaryResult.profSheetCount} pcs'],
                ['Sheet metal area', '${formatNumber(summaryResult.extraSheetAreaSqm)} m2'],
                ['Materials', '${formatMoney(summaryResult.materialCost)} RUB'],
                ['Overheads', '${formatMoney(summaryResult.overheadsCost)} RUB'],
                ['Total', '${formatMoney(summaryResult.totalCost)} RUB'],
              ]),
            ),
            if (includeFence) ...[
              pw.SizedBox(height: 18),
              pw.Text('Fence', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(2),
                },
                children: buildKeyValueRows([
                  ['Posts', '${fence.postsCount} pcs'],
                  ['Rails', '${fence.railRows} rows'],
                  ['Exact pipe', '${formatNumber(fence.exactPipeLengthM)} m'],
                  ['Commercial pipe', '${formatNumber(fence.commercialPipeLengthM)} m'],
                  ['Stock bars', '${fence.whips6m} pcs'],
                  ['Concrete', '${formatNumber(fence.concreteVolumeM3)} m3'],
                  ['Fasteners', '${fence.fastenersCount} pcs'],
                  ['Total', '${formatMoney(fence.totalCost)} RUB'],
                ]),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Fence profile sheet cut map', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: buildSheetRows(fence.cutPlan.sheetPieces),
              ),
            ],
            if (includeGarage) ...[
              pw.SizedBox(height: 18),
              pw.Text('Garage', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(2),
                },
                children: buildKeyValueRows([
                  ['Posts', '${garage.wallPostsCount} pcs'],
                  ['Exact pipe', '${formatNumber(garage.exactPipeLengthM)} m'],
                  ['Commercial pipe', '${formatNumber(garage.commercialPipeLengthM)} m'],
                  ['Stock bars', '${garage.whips6m} pcs'],
                  ['Wall strips', '${garage.cutPlan.wallStripCount} pcs'],
                  ['Roof strips', '${garage.cutPlan.roofStripCount} pcs'],
                  ['Fasteners', '${garage.fastenersCount} pcs'],
                  ['Total', '${formatMoney(garage.totalCost)} RUB'],
                ]),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Garage wall cut map', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: buildSheetRows(garage.cutPlan.wallPieces),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Garage roof cut map', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: buildSheetRows(garage.cutPlan.roofPieces),
              ),
            ],
            if (includeSheet) ...[
              pw.SizedBox(height: 18),
              pw.Text('Sheet metal', style: bold),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(2),
                },
                children: buildKeyValueRows([
                  ['Kind', sheetKindLabel(sheetKind)],
                  ['Area', '${formatNumber(sheet.totalAreaSqm)} m2'],
                  ['Weight', '${formatNumber(sheet.totalWeightKg)} kg'],
                  ['Cost', '${formatMoney(sheet.totalCost)} RUB'],
                ]),
              ),
            ],
          ];
        },
      ),
    );

    await file.writeAsBytes(await pdf.save());
    lastSavedPdfPath = file.path;
    notifyListeners();
    return file;
  }

  static String _stringValue(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value;
    return fallback;
  }

  static double _doubleValue(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
    }
    return fallback;
  }

  static int _intValue(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _boundedIntValue(
    dynamic value,
    int fallback, {
    required int maxValue,
  }) {
    final raw = _intValue(value, fallback);
    return raw.clamp(0, maxValue).toInt();
  }

  static bool _boolValue(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  static RoofKind _roofKindValue(dynamic value, RoofKind fallback) {
    if (value is String) {
      for (final item in RoofKind.values) {
        if (item.name == value) return item;
      }
    }
    return fallback;
  }

  static SheetKind _sheetKindValue(dynamic value, SheetKind fallback) {
    if (value is String) {
      for (final item in SheetKind.values) {
        if (item.name == value) return item;
      }
    }
    return fallback;
  }
}

class CalculationService {
  static FenceResult fence(EstimatorModel model) {
    final claddedRun = math.max(
      0,
      model.fenceLengthM -
          (model.fenceHasGate ? model.fenceGateWidthM : 0) -
          (model.fenceHasWicket ? model.fenceWicketWidthM : 0),
    );

    final sections = splitByPreferredStep(claddedRun, model.fencePostStepM);
    final spanCount = math.max(1, (model.fenceLengthM / model.fencePostStepM).ceil());
    final postsCount = spanCount +
        1 +
        (model.fenceHasGate ? 2 : 0) +
        (model.fenceHasWicket ? 2 : 0);
    final railRows = model.fenceHeightM <= 2.0 ? 2 : 3;

    final pipePieces = <PipePiece>[
      PipePiece(
        group: 'Столбы',
        label: 'Столб',
        lengthM: model.fenceHeightM + model.fencePostEmbedM,
        quantity: postsCount,
      ),
      for (var i = 0; i < sections.length; i++)
        PipePiece(
          group: 'Лаги',
          label: 'Секция ${i + 1}',
          lengthM: sections[i],
          quantity: railRows,
        ),
    ];

    if (model.fenceHasGate) {
      final leafWidth = model.fenceGateWidthM / 2;
      pipePieces.addAll([
        PipePiece(
          group: 'Ворота',
          label: 'Стойка створки ворот',
          lengthM: model.fenceHeightM,
          quantity: 4,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
        PipePiece(
          group: 'Ворота',
          label: 'Перемычка створки ворот',
          lengthM: leafWidth,
          quantity: 4,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
        PipePiece(
          group: 'Ворота',
          label: 'Диагональ створки ворот',
          lengthM: math.sqrt(leafWidth * leafWidth + model.fenceHeightM * model.fenceHeightM),
          quantity: 2,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
      ]);
    }

    if (model.fenceHasWicket) {
      pipePieces.addAll([
        PipePiece(
          group: 'Калитка',
          label: 'Стойка калитки',
          lengthM: model.fenceHeightM,
          quantity: 2,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
        PipePiece(
          group: 'Калитка',
          label: 'Перемычка калитки',
          lengthM: model.fenceWicketWidthM,
          quantity: 2,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
        PipePiece(
          group: 'Калитка',
          label: 'Диагональ калитки',
          lengthM: math.sqrt(
            model.fenceWicketWidthM * model.fenceWicketWidthM +
                model.fenceHeightM * model.fenceHeightM,
          ),
          quantity: 1,
          startAngle: CutAngle.miter45,
          endAngle: CutAngle.miter45,
        ),
      ]);
    }

    final stockBars = CutPlanner.pack(
      pipePieces,
      stockLengthM: model.stockLengthM,
      sawKerfM: model.sawKerfMm / 1000,
    );

    final exactPipeLength = pipePieces.fold<double>(
      0,
      (sum, item) => sum + item.totalLengthM,
    );
    final commercialFactor = 1 + model.fenceWastePercent / 100;
    final commercialPipeLength =
        stockBars.length * model.stockLengthM * commercialFactor;
    final pipeWeight = commercialPipeLength * model.pipe.weightPerMeterKg;

    final sheetPieces = <SheetCutPiece>[];
    for (var i = 0; i < sections.length; i++) {
      sheetPieces.addAll(
        buildSheetStrips(
          'Секция ${i + 1}',
          widthM: sections[i],
          heightM: model.fenceHeightM,
          profile: model.profSheet,
        ),
      );
    }
    if (model.fenceHasGate && model.fenceGateCladded) {
      final leafWidth = model.fenceGateWidthM / 2;
      sheetPieces.addAll(
        buildSheetStrips(
          'Ворота створка 1',
          widthM: leafWidth,
          heightM: model.fenceHeightM,
          profile: model.profSheet,
        ),
      );
      sheetPieces.addAll(
        buildSheetStrips(
          'Ворота створка 2',
          widthM: leafWidth,
          heightM: model.fenceHeightM,
          profile: model.profSheet,
        ),
      );
    }
    if (model.fenceHasWicket && model.fenceWicketCladded) {
      sheetPieces.addAll(
        buildSheetStrips(
          'Калитка',
          widthM: model.fenceWicketWidthM,
          heightM: model.fenceHeightM,
          profile: model.profSheet,
        ),
      );
    }

    final exactSheetArea = sheetPieces.fold<double>(
      0,
      (sum, item) => sum + item.coverWidthM * item.heightM * item.quantity,
    );
    final purchasedSheetArea = sheetPieces.fold<double>(
          0,
          (sum, item) => sum + item.purchasedAreaSqm,
        ) *
        commercialFactor;
    final fastenersCount = sheetPieces.fold<int>(
      0,
      (sum, item) => sum + item.quantity * (model.fenceHeightM <= 2 ? 6 : 8),
    );

    final holeRadius = 0.1;
    final concreteVolume =
        postsCount * math.pi * holeRadius * holeRadius * model.fencePostEmbedM;

    final pipeCost = commercialPipeLength * model.pipePricePerM;
    final sheetCost = purchasedSheetArea * model.profSheetPricePerSqm;
    final fastenersCost = fastenersCount * model.fastenerPrice;
    final concreteCost = concreteVolume * model.concretePricePerM3;
    final totalCost = pipeCost + sheetCost + fastenersCost + concreteCost;

    final cutPlan = FenceCutPlan(
      sheetPieces: sheetPieces,
      pipePieces: pipePieces,
      stockBars: stockBars,
      exactSheetAreaSqm: exactSheetArea,
      purchasedSheetAreaSqm: purchasedSheetArea,
      stripCount: sheetPieces.fold<int>(0, (sum, item) => sum + item.quantity),
      miter45Cuts: pipePieces.fold<int>(0, (sum, item) => sum + item.totalMiterCuts),
    );

    return FenceResult(
      exactPipeLengthM: exactPipeLength,
      commercialPipeLengthM: commercialPipeLength,
      pipeWeightKg: pipeWeight,
      postsCount: postsCount,
      railRows: railRows,
      fastenersCount: fastenersCount,
      concreteVolumeM3: concreteVolume,
      pipeCost: pipeCost,
      sheetCost: sheetCost,
      fastenersCost: fastenersCost,
      concreteCost: concreteCost,
      totalCost: totalCost,
      whips6m: stockBars.length,
      cutPlan: cutPlan,
    );
  }

  static GarageResult garage(EstimatorModel model) {
    final length = model.garageLengthM;
    final width = model.garageWidthM;
    final height = model.garageHeightM;
    final frameStep = model.garageFrameStepM;
    final frameCount = math.max(2, (length / frameStep).ceil() + 1);
    final roofSlopeRad = _degToRad(model.garageRoofSlopeDeg);
    final singleSlopeSpan = width / math.cos(roofSlopeRad);
    final halfSlopeSpan = (width / 2) / math.cos(roofSlopeRad);
    final roofRise = model.garageRoofKind == RoofKind.singleSlope
        ? width * math.tan(roofSlopeRad)
        : (width / 2) * math.tan(roofSlopeRad);

    final wallPostsCount = frameCount * 2 + 2 * (math.max(0, (width / frameStep).ceil()) - 1);
    final sideGirtsRows = height <= 2.7 ? 2 : 3;

    final pipePieces = <PipePiece>[
      PipePiece(
        group: 'Стены',
        label: 'Стойка стены',
        lengthM: height,
        quantity: wallPostsCount,
      ),
      PipePiece(
        group: 'Стены',
        label: 'Левая стена лаги',
        lengthM: length,
        quantity: sideGirtsRows,
      ),
      PipePiece(
        group: 'Стены',
        label: 'Правая стена лаги',
        lengthM: length,
        quantity: sideGirtsRows,
      ),
      PipePiece(
        group: 'Стены',
        label: 'Задняя стена лаги',
        lengthM: width,
        quantity: sideGirtsRows,
      ),
      PipePiece(
        group: 'Стены',
        label: 'Передняя стена лаги',
        lengthM: math.max(0.4, width - model.garageGateWidthM),
        quantity: sideGirtsRows,
      ),
    ];

    if (model.garageRoofKind == RoofKind.singleSlope) {
      pipePieces.add(
        PipePiece(
          group: 'Кровля',
          label: 'Стропило односкатной крыши',
          lengthM: singleSlopeSpan + model.garageRoofOverhangM * 2,
          quantity: frameCount,
        ),
      );
      final purlinRows = math.max(3, ((singleSlopeSpan + model.garageRoofOverhangM) / 1.1).ceil() + 1);
      pipePieces.add(
        PipePiece(
          group: 'Кровля',
          label: 'Прогон односкатной крыши',
          lengthM: length + model.garageRoofOverhangM * 2,
          quantity: purlinRows,
        ),
      );
    } else {
      pipePieces.add(
        PipePiece(
          group: 'Кровля',
          label: 'Стропило двускатной крыши',
          lengthM: halfSlopeSpan + model.garageRoofOverhangM,
          quantity: frameCount * 2,
        ),
      );
      pipePieces.add(
        PipePiece(
          group: 'Кровля',
          label: 'Стяжка фермы',
          lengthM: width,
          quantity: frameCount,
        ),
      );
      final purlinRows = math.max(3, ((halfSlopeSpan + model.garageRoofOverhangM) / 1.1).ceil() + 1);
      pipePieces.add(
        PipePiece(
          group: 'Кровля',
          label: 'Прогон ската',
          lengthM: length + model.garageRoofOverhangM * 2,
          quantity: purlinRows * 2,
        ),
      );
    }

    pipePieces.addAll([
      PipePiece(
        group: 'Ворота гаража',
        label: 'Стойка ворот',
        lengthM: model.garageGateHeightM,
        quantity: 4,
        startAngle: CutAngle.miter45,
        endAngle: CutAngle.miter45,
      ),
      PipePiece(
        group: 'Ворота гаража',
        label: 'Перемычка ворот',
        lengthM: model.garageGateWidthM / 2,
        quantity: 4,
        startAngle: CutAngle.miter45,
        endAngle: CutAngle.miter45,
      ),
      PipePiece(
        group: 'Ворота гаража',
        label: 'Диагональ ворот',
        lengthM: math.sqrt(
          math.pow(model.garageGateWidthM / 2, 2) +
              math.pow(model.garageGateHeightM, 2),
        ),
        quantity: 2,
        startAngle: CutAngle.miter45,
        endAngle: CutAngle.miter45,
      ),
    ]);

    final stockBars = CutPlanner.pack(
      pipePieces,
      stockLengthM: model.stockLengthM,
      sawKerfM: model.sawKerfMm / 1000,
    );

    final exactPipeLength = pipePieces.fold<double>(
      0,
      (sum, item) => sum + item.totalLengthM,
    );
    final commercialFactor = 1 + model.garageWastePercent / 100;
    final commercialPipeLength =
        stockBars.length * model.stockLengthM * commercialFactor;
    final pipeWeight = commercialPipeLength * model.pipe.weightPerMeterKg;

    final wallPieces = <SheetCutPiece>[
      ...buildSheetStrips(
        'Задняя стена',
        widthM: width,
        heightM: height,
        profile: model.profSheet,
      ),
      ...buildSheetStrips(
        'Левая стена',
        widthM: length,
        heightM: height,
        profile: model.profSheet,
      ),
      ...buildSheetStrips(
        'Правая стена',
        widthM: length,
        heightM: height,
        profile: model.profSheet,
      ),
    ];

    final frontSideWidth = math.max(0, (width - model.garageGateWidthM) / 2);
    if (frontSideWidth > 0.02) {
      wallPieces.addAll(
        buildSheetStrips(
          'Передняя стена слева',
          widthM: frontSideWidth,
          heightM: height,
          profile: model.profSheet,
        ),
      );
      wallPieces.addAll(
        buildSheetStrips(
          'Передняя стена справа',
          widthM: frontSideWidth,
          heightM: height,
          profile: model.profSheet,
        ),
      );
    }
    final frontHeaderHeight = math.max(0, height - model.garageGateHeightM);
    if (frontHeaderHeight > 0.05) {
      wallPieces.addAll(
        buildSheetStrips(
          'Передняя перемычка над воротами',
          widthM: model.garageGateWidthM,
          heightM: frontHeaderHeight,
          profile: model.profSheet,
        ),
      );
    }

    final roofPieces = <SheetCutPiece>[];
    if (model.garageRoofKind == RoofKind.singleSlope) {
      final roofStripHeight = singleSlopeSpan + model.garageRoofOverhangM * 2;
      roofPieces.addAll(
        buildSheetStrips(
          'Скат крыши',
          widthM: length + model.garageRoofOverhangM * 2,
          heightM: roofStripHeight,
          profile: model.profSheet,
        ),
      );
    } else {
      final roofStripHeight = halfSlopeSpan + model.garageRoofOverhangM;
      roofPieces.addAll(
        buildSheetStrips(
          'Левый скат',
          widthM: length + model.garageRoofOverhangM * 2,
          heightM: roofStripHeight,
          profile: model.profSheet,
        ),
      );
      roofPieces.addAll(
        buildSheetStrips(
          'Правый скат',
          widthM: length + model.garageRoofOverhangM * 2,
          heightM: roofStripHeight,
          profile: model.profSheet,
        ),
      );
      if (roofRise > 0.01) {
        wallPieces.addAll(
          buildSheetStrips(
            'Фронтон слева',
            widthM: width / 2,
            heightM: roofRise,
            profile: model.profSheet,
          ),
        );
        wallPieces.addAll(
          buildSheetStrips(
            'Фронтон справа',
            widthM: width / 2,
            heightM: roofRise,
            profile: model.profSheet,
          ),
        );
      }
    }

    final wallExactArea = wallPieces.fold<double>(
      0,
      (sum, item) => sum + item.coverWidthM * item.heightM * item.quantity,
    );
    final wallPurchasedArea = wallPieces.fold<double>(
          0,
          (sum, item) => sum + item.purchasedAreaSqm,
        ) *
        commercialFactor;
    final roofExactArea = roofPieces.fold<double>(
      0,
      (sum, item) => sum + item.coverWidthM * item.heightM * item.quantity,
    );
    final roofPurchasedArea = roofPieces.fold<double>(
          0,
          (sum, item) => sum + item.purchasedAreaSqm,
        ) *
        commercialFactor;

    final fastenersCount = wallPieces.fold<int>(
          0,
          (sum, item) => sum + item.quantity * 8,
        ) +
        roofPieces.fold<int>(
          0,
          (sum, item) => sum + item.quantity * 10,
        );

    final pipeCost = commercialPipeLength * model.pipePricePerM;
    final wallSheetCost = wallPurchasedArea * model.profSheetPricePerSqm;
    final roofSheetCost = roofPurchasedArea * model.profSheetPricePerSqm;
    final fastenersCost = fastenersCount * model.fastenerPrice;
    final totalCost = pipeCost + wallSheetCost + roofSheetCost + fastenersCost;

    final cutPlan = GarageCutPlan(
      wallPieces: wallPieces,
      roofPieces: roofPieces,
      pipePieces: pipePieces,
      stockBars: stockBars,
      wallExactAreaSqm: wallExactArea,
      wallPurchasedAreaSqm: wallPurchasedArea,
      roofExactAreaSqm: roofExactArea,
      roofPurchasedAreaSqm: roofPurchasedArea,
      wallStripCount: wallPieces.fold<int>(0, (sum, item) => sum + item.quantity),
      roofStripCount: roofPieces.fold<int>(0, (sum, item) => sum + item.quantity),
      miter45Cuts: pipePieces.fold<int>(0, (sum, item) => sum + item.totalMiterCuts),
    );

    return GarageResult(
      exactPipeLengthM: exactPipeLength,
      commercialPipeLengthM: commercialPipeLength,
      pipeWeightKg: pipeWeight,
      wallPostsCount: wallPostsCount,
      fastenersCount: fastenersCount,
      pipeCost: pipeCost,
      wallSheetCost: wallSheetCost,
      roofSheetCost: roofSheetCost,
      fastenersCost: fastenersCost,
      totalCost: totalCost,
      whips6m: stockBars.length,
      cutPlan: cutPlan,
    );
  }

  static SheetMetalResult sheetMetal(EstimatorModel model) {
    final areaOne = model.sheetLengthM * model.sheetWidthM;
    final totalArea = areaOne * model.sheetCount;
    final thicknessM = model.sheetThicknessMm / 1000;
    const density = 7850.0;
    final totalWeight = totalArea * thicknessM * density;
    final totalCost = model.sheetCount * model.sheetPricePerPiece;

    return SheetMetalResult(
      totalAreaSqm: totalArea,
      totalWeightKg: totalWeight,
      totalCost: totalCost,
    );
  }

  static ProjectSummaryResult summary(EstimatorModel model) {
    final fence = model.fenceResult;
    final garage = model.garageResult;
    final sheet = model.sheetResult;

    final pipeLength = (model.includeFence ? fence.commercialPipeLengthM : 0) +
        (model.includeGarage ? garage.commercialPipeLengthM : 0);

    final pipeWeight = (model.includeFence ? fence.pipeWeightKg : 0) +
        (model.includeGarage ? garage.pipeWeightKg : 0);

    final profArea = (model.includeFence ? fence.cutPlan.purchasedSheetAreaSqm : 0) +
        (model.includeGarage
            ? garage.cutPlan.wallPurchasedAreaSqm + garage.cutPlan.roofPurchasedAreaSqm
            : 0);

    final profSheets = (model.includeFence ? fence.cutPlan.stripCount : 0) +
        (model.includeGarage
            ? garage.cutPlan.wallStripCount + garage.cutPlan.roofStripCount
            : 0);

    final extraSheetArea = model.includeSheet ? sheet.totalAreaSqm : 0;

    final materials = (model.includeFence ? fence.totalCost : 0) +
        (model.includeGarage ? garage.totalCost : 0) +
        (model.includeSheet ? sheet.totalCost : 0);

    final overheads =
        model.deliveryCost + model.weldingCost + model.paintCost + model.mountingCost;

    return ProjectSummaryResult(
      pipeLengthM: pipeLength,
      pipeWeightKg: pipeWeight,
      profSheetPurchasedAreaSqm: profArea,
      profSheetCount: profSheets,
      extraSheetAreaSqm: extraSheetArea,
      materialCost: materials,
      overheadsCost: overheads,
      totalCost: materials + overheads,
    );
  }

  static double _degToRad(double value) => value * math.pi / 180;
}

class CutPlanner {
  static List<StockBar> pack(
    List<PipePiece> pieces, {
    required double stockLengthM,
    required double sawKerfM,
  }) {
    final expanded = <PipeCutUnit>[
      for (final piece in pieces)
        for (var i = 0; i < piece.quantity; i++)
          PipeCutUnit(
            group: piece.group,
            label: piece.label,
            lengthM: piece.lengthM,
            startAngle: piece.startAngle,
            endAngle: piece.endAngle,
          ),
    ]..sort((a, b) => b.lengthM.compareTo(a.lengthM));

    final builders = <_StockBarBuilder>[];
    for (final unit in expanded) {
      _StockBarBuilder? best;
      var bestWaste = double.infinity;
      for (final candidate in builders) {
        final extraKerf = candidate.items.isEmpty ? 0 : sawKerfM;
        if (candidate.usedLengthM + extraKerf + unit.lengthM <= stockLengthM + 0.000001) {
          final waste = stockLengthM - (candidate.usedLengthM + extraKerf + unit.lengthM);
          if (waste < bestWaste) {
            bestWaste = waste;
            best = candidate;
          }
        }
      }
      final target = best ?? _StockBarBuilder(index: builders.length + 1);
      if (!builders.contains(target)) {
        builders.add(target);
      }
      target.add(unit, sawKerfM);
    }

    return [
      for (final builder in builders)
        StockBar(
          index: builder.index,
          stockLengthM: stockLengthM,
          usedLengthM: builder.usedLengthM,
          items: List<PipeCutUnit>.unmodifiable(builder.items),
        ),
    ];
  }
}

class _StockBarBuilder {
  _StockBarBuilder({required this.index});

  final int index;
  final List<PipeCutUnit> items = [];
  double usedLengthM = 0;

  void add(PipeCutUnit unit, double sawKerfM) {
    if (items.isNotEmpty) {
      usedLengthM += sawKerfM;
    }
    items.add(unit);
    usedLengthM += unit.lengthM;
  }
}

List<double> splitByPreferredStep(double totalLengthM, double preferredStepM) {
  final safeStep = preferredStepM <= 0 ? totalLengthM : preferredStepM;
  final result = <double>[];
  var remaining = totalLengthM;
  while (remaining > 0.0001) {
    final value = math.min(safeStep, remaining);
    result.add(value);
    remaining -= value;
  }
  if (result.isEmpty) {
    result.add(0);
  }
  return result;
}

List<SheetCutPiece> buildSheetStrips(
  String group, {
  required double widthM,
  required double heightM,
  required ProfSheetProfile profile,
}) {
  if (widthM <= 0.0001 || heightM <= 0.0001) {
    return const [];
  }
  final pieces = <SheetCutPiece>[];
  final ratio = profile.fullWidthM / profile.usefulWidthM;
  var remaining = widthM;
  while (remaining > 0.0001) {
    final cover = math.min(profile.usefulWidthM, remaining);
    final actual = math.min(profile.fullWidthM, cover * ratio);
    pieces.add(
      SheetCutPiece(
        group: group,
        coverWidthM: cover,
        actualWidthM: actual,
        heightM: heightM,
      ),
    );
    remaining -= cover;
  }
  return pieces;
}

class AggregatedSheetPiece {
  const AggregatedSheetPiece({
    required this.group,
    required this.actualWidthM,
    required this.coverWidthM,
    required this.heightM,
    required this.quantity,
  });

  final String group;
  final double actualWidthM;
  final double coverWidthM;
  final double heightM;
  final int quantity;
}

List<AggregatedSheetPiece> aggregateSheetPieces(List<SheetCutPiece> items) {
  final grouped = <String, AggregatedSheetPiece>{};
  for (final item in items) {
    final key =
        '${item.group}|${item.actualWidthM.toStringAsFixed(3)}|${item.heightM.toStringAsFixed(3)}|${item.coverWidthM.toStringAsFixed(3)}';
    final existing = grouped[key];
    if (existing == null) {
      grouped[key] = AggregatedSheetPiece(
        group: item.group,
        actualWidthM: item.actualWidthM,
        coverWidthM: item.coverWidthM,
        heightM: item.heightM,
        quantity: item.quantity,
      );
    } else {
      grouped[key] = AggregatedSheetPiece(
        group: existing.group,
        actualWidthM: existing.actualWidthM,
        coverWidthM: existing.coverWidthM,
        heightM: existing.heightM,
        quantity: existing.quantity + item.quantity,
      );
    }
  }
  return grouped.values.toList()
    ..sort((a, b) => a.group.compareTo(b.group));
}

class FencePage extends StatelessWidget {
  const FencePage({super.key, required this.model});

  final EstimatorModel model;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final result = model.fenceResult;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Забор из профнастила',
              subtitle: 'Точный расчет профлиста по секциям, воротам и калитке.',
              children: [
                SwitchListTile(
                  title: const Text('Включить забор в проект'),
                  value: model.includeFence,
                  onChanged: (value) {
                    model.includeFence = value;
                    model.notify();
                  },
                ),
                ProjectNameField(model: model),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: model.selectedPipeIndex,
                  decoration: const InputDecoration(labelText: 'Профиль трубы'),
                  items: [
                    for (var i = 0; i < model.pipeProfiles.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${model.pipeProfiles[i].name} • ${formatNumber(model.pipeProfiles[i].weightPerMeterKg)} кг/м',
                        ),
                      ),
                  ],
                  onChanged: (value) => value == null ? null : model.setPipeIndex(value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: model.selectedProfSheetIndex,
                  decoration: const InputDecoration(labelText: 'Профнастил'),
                  items: [
                    for (var i = 0; i < model.profSheets.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          '${model.profSheets[i].name} • полезная ${formatNumber(model.profSheets[i].usefulWidthM)} м',
                        ),
                      ),
                  ],
                  onChanged: (value) => value == null ? null : model.setProfSheetIndex(value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Длина забора, м',
                        value: model.fenceLengthM,
                        onChanged: (value) {
                          model.fenceLengthM = math.max(1, value);
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Высота, м',
                        value: model.fenceHeightM,
                        onChanged: (value) {
                          model.fenceHeightM = value.clamp(1.0, 4.0).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Шаг столбов, м',
                        value: model.fencePostStepM,
                        onChanged: (value) {
                          model.fencePostStepM = value.clamp(1.5, 4.0).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Заглубление столба, м',
                        value: model.fencePostEmbedM,
                        onChanged: (value) {
                          model.fencePostEmbedM = value.clamp(0.6, 2.0).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Есть ворота'),
                  value: model.fenceHasGate,
                  onChanged: (value) {
                    model.fenceHasGate = value;
                    model.notify();
                  },
                ),
                if (model.fenceHasGate) ...[
                  DecimalField(
                    label: 'Ширина ворот, м',
                    value: model.fenceGateWidthM,
                    onChanged: (value) {
                      model.fenceGateWidthM = value.clamp(1.5, 8.0).toDouble();
                      model.notify();
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Обшивать ворота профнастилом'),
                    value: model.fenceGateCladded,
                    onChanged: (value) {
                      model.fenceGateCladded = value;
                      model.notify();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Есть калитка'),
                  value: model.fenceHasWicket,
                  onChanged: (value) {
                    model.fenceHasWicket = value;
                    model.notify();
                  },
                ),
                if (model.fenceHasWicket) ...[
                  DecimalField(
                    label: 'Ширина калитки, м',
                    value: model.fenceWicketWidthM,
                    onChanged: (value) {
                      model.fenceWicketWidthM = value.clamp(0.7, 1.5).toDouble();
                      model.notify();
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Обшивать калитку профнастилом'),
                    value: model.fenceWicketCladded,
                    onChanged: (value) {
                      model.fenceWicketCladded = value;
                      model.notify();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                DecimalField(
                  label: 'Коммерческий запас, %',
                  value: model.fenceWastePercent,
                  onChanged: (value) {
                    model.fenceWastePercent = value.clamp(0, 20).toDouble();
                    model.notify();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '3D-эскиз забора',
              subtitle: 'Тяни пальцем по рисунку, чтобы повернуть модель.',
              children: [
                SizedBox(
                  height: 280,
                  child: SketchViewer(
                    kind: SketchKind.fence,
                    length: model.fenceLengthM,
                    width: 0,
                    height: model.fenceHeightM,
                    fencePosts: result.postsCount,
                    roofKind: RoofKind.singleSlope,
                    roofAngleDeg: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Расчет по забору',
              children: [
                MetricsWrap(
                  items: [
                    MetricItem('Труба точно', '${formatNumber(result.exactPipeLengthM)} м'),
                    MetricItem('Труба коммерч.', '${formatNumber(result.commercialPipeLengthM)} м'),
                    MetricItem('Вес трубы', '${formatNumber(result.pipeWeightKg)} кг'),
                    MetricItem('Хлысты 6 м', '${result.whips6m} шт'),
                    MetricItem('Столбы', '${result.postsCount} шт'),
                    MetricItem('Лаги', '${result.railRows} ряда'),
                    MetricItem('Полосы профлиста', '${result.cutPlan.stripCount} шт'),
                    MetricItem('Профлист точно', '${formatNumber(result.cutPlan.exactSheetAreaSqm)} м²'),
                    MetricItem('Профлист коммерч.', '${formatNumber(result.cutPlan.purchasedSheetAreaSqm)} м²'),
                    MetricItem('Рез 45°', '${result.cutPlan.miter45Cuts} торцов'),
                    MetricItem('Саморезы', '${result.fastenersCount} шт'),
                    MetricItem('Бетон', '${formatNumber(result.concreteVolumeM3)} м³'),
                  ],
                ),
                const Divider(height: 24),
                CostLine(label: 'Труба', value: result.pipeCost),
                CostLine(label: 'Профнастил', value: result.sheetCost),
                CostLine(label: 'Саморезы', value: result.fastenersCost),
                CostLine(label: 'Бетон', value: result.concreteCost),
                const Divider(height: 24),
                CostLine(label: 'Итого по забору', value: result.totalCost, emphasize: true),
              ],
            ),
            const SizedBox(height: 16),
            PipeCutPlanCard(
              title: 'Карта распила трубы',
              stockBars: result.cutPlan.stockBars,
              pipePieces: result.cutPlan.pipePieces,
              stockLengthM: model.stockLengthM,
            ),
            const SizedBox(height: 16),
            SheetCutPlanCard(
              title: 'Карта раскроя профнастила',
              subtitle: 'Последний лист каждой секции режется по полезной ширине.',
              pieces: result.cutPlan.sheetPieces,
              exactAreaSqm: result.cutPlan.exactSheetAreaSqm,
              purchasedAreaSqm: result.cutPlan.purchasedSheetAreaSqm,
            ),
          ],
        );
      },
    );
  }
}

class GaragePage extends StatelessWidget {
  const GaragePage({super.key, required this.model});

  final EstimatorModel model;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final result = model.garageResult;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Гараж из профтрубы и профнастила',
              subtitle: 'Точные карты распила трубы и раскроя листа по стенам и крыше.',
              children: [
                SwitchListTile(
                  title: const Text('Включить гараж в проект'),
                  value: model.includeGarage,
                  onChanged: (value) {
                    model.includeGarage = value;
                    model.notify();
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Длина, м',
                        value: model.garageLengthM,
                        onChanged: (value) {
                          model.garageLengthM = value.clamp(3, 18).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Ширина, м',
                        value: model.garageWidthM,
                        onChanged: (value) {
                          model.garageWidthM = value.clamp(2.5, 12).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Высота, м',
                        value: model.garageHeightM,
                        onChanged: (value) {
                          model.garageHeightM = value.clamp(2, 5).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RoofKind>(
                  value: model.garageRoofKind,
                  decoration: const InputDecoration(labelText: 'Тип крыши'),
                  items: const [
                    DropdownMenuItem(
                      value: RoofKind.singleSlope,
                      child: Text('Односкатная'),
                    ),
                    DropdownMenuItem(
                      value: RoofKind.gable,
                      child: Text('Двускатная'),
                    ),
                  ],
                  onChanged: (value) => value == null ? null : model.setRoofKind(value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Шаг каркаса, м',
                        value: model.garageFrameStepM,
                        onChanged: (value) {
                          model.garageFrameStepM = value.clamp(1.5, 3).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Свес крыши, м',
                        value: model.garageRoofOverhangM,
                        onChanged: (value) {
                          model.garageRoofOverhangM = value.clamp(0, 1).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Угол крыши, °',
                        value: model.garageRoofSlopeDeg,
                        onChanged: (value) {
                          model.garageRoofSlopeDeg = value.clamp(5, 45).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Ширина ворот, м',
                        value: model.garageGateWidthM,
                        onChanged: (value) {
                          model.garageGateWidthM = value.clamp(2, model.garageWidthM).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Высота ворот, м',
                        value: model.garageGateHeightM,
                        onChanged: (value) {
                          model.garageGateHeightM = value.clamp(1.8, model.garageHeightM).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DecimalField(
                  label: 'Коммерческий запас, %',
                  value: model.garageWastePercent,
                  onChanged: (value) {
                    model.garageWastePercent = value.clamp(0, 20).toDouble();
                    model.notify();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '3D-эскиз гаража',
              subtitle: 'Поворот жестом, масштаб щипком.',
              children: [
                SizedBox(
                  height: 320,
                  child: SketchViewer(
                    kind: SketchKind.garage,
                    length: model.garageLengthM,
                    width: model.garageWidthM,
                    height: model.garageHeightM,
                    fencePosts: 0,
                    roofKind: model.garageRoofKind,
                    roofAngleDeg: model.garageRoofSlopeDeg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Расчет по гаражу',
              children: [
                MetricsWrap(
                  items: [
                    MetricItem('Труба точно', '${formatNumber(result.exactPipeLengthM)} м'),
                    MetricItem('Труба коммерч.', '${formatNumber(result.commercialPipeLengthM)} м'),
                    MetricItem('Вес трубы', '${formatNumber(result.pipeWeightKg)} кг'),
                    MetricItem('Хлысты 6 м', '${result.whips6m} шт'),
                    MetricItem('Стойки', '${result.wallPostsCount} шт'),
                    MetricItem('Профлист стены', '${result.cutPlan.wallStripCount} полос'),
                    MetricItem('Профлист кровля', '${result.cutPlan.roofStripCount} полос'),
                    MetricItem('Стены точно', '${formatNumber(result.cutPlan.wallExactAreaSqm)} м²'),
                    MetricItem('Стены коммерч.', '${formatNumber(result.cutPlan.wallPurchasedAreaSqm)} м²'),
                    MetricItem('Кровля точно', '${formatNumber(result.cutPlan.roofExactAreaSqm)} м²'),
                    MetricItem('Кровля коммерч.', '${formatNumber(result.cutPlan.roofPurchasedAreaSqm)} м²'),
                    MetricItem('Рез 45°', '${result.cutPlan.miter45Cuts} торцов'),
                    MetricItem('Саморезы', '${result.fastenersCount} шт'),
                  ],
                ),
                const Divider(height: 24),
                CostLine(label: 'Труба', value: result.pipeCost),
                CostLine(label: 'Профнастил стен', value: result.wallSheetCost),
                CostLine(label: 'Профнастил кровли', value: result.roofSheetCost),
                CostLine(label: 'Саморезы', value: result.fastenersCost),
                const Divider(height: 24),
                CostLine(label: 'Итого по гаражу', value: result.totalCost, emphasize: true),
              ],
            ),
            const SizedBox(height: 16),
            PipeCutPlanCard(
              title: 'Карта распила трубы',
              stockBars: result.cutPlan.stockBars,
              pipePieces: result.cutPlan.pipePieces,
              stockLengthM: model.stockLengthM,
            ),
            const SizedBox(height: 16),
            SheetCutPlanCard(
              title: 'Карта раскроя стенового профнастила',
              pieces: result.cutPlan.wallPieces,
              exactAreaSqm: result.cutPlan.wallExactAreaSqm,
              purchasedAreaSqm: result.cutPlan.wallPurchasedAreaSqm,
            ),
            const SizedBox(height: 16),
            SheetCutPlanCard(
              title: 'Карта раскроя кровельного профнастила',
              pieces: result.cutPlan.roofPieces,
              exactAreaSqm: result.cutPlan.roofExactAreaSqm,
              purchasedAreaSqm: result.cutPlan.roofPurchasedAreaSqm,
            ),
          ],
        );
      },
    );
  }
}

class SheetPage extends StatelessWidget {
  const SheetPage({super.key, required this.model});

  final EstimatorModel model;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final result = model.sheetResult;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Листовой металл',
              subtitle: 'Отдельный расчет листа вне профнастила.',
              children: [
                SwitchListTile(
                  title: const Text('Включить лист в проект'),
                  value: model.includeSheet,
                  onChanged: (value) {
                    model.includeSheet = value;
                    model.notify();
                  },
                ),
                DropdownButtonFormField<SheetKind>(
                  value: model.sheetKind,
                  decoration: const InputDecoration(labelText: 'Тип листа'),
                  items: const [
                    DropdownMenuItem(
                      value: SheetKind.hotRolled,
                      child: Text('Г/к лист'),
                    ),
                    DropdownMenuItem(
                      value: SheetKind.coldRolled,
                      child: Text('Х/к лист'),
                    ),
                    DropdownMenuItem(
                      value: SheetKind.galvanized,
                      child: Text('Оцинкованный'),
                    ),
                  ],
                  onChanged: (value) => value == null ? null : model.setSheetKind(value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Длина листа, м',
                        value: model.sheetLengthM,
                        onChanged: (value) {
                          model.sheetLengthM = value.clamp(0.5, 12).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Ширина листа, м',
                        value: model.sheetWidthM,
                        onChanged: (value) {
                          model.sheetWidthM = value.clamp(0.5, 3).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Толщина, мм',
                        value: model.sheetThicknessMm,
                        onChanged: (value) {
                          model.sheetThicknessMm = value.clamp(0.35, 20).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: IntegerField(
                        label: 'Количество листов',
                        value: model.sheetCount,
                        onChanged: (value) {
                          model.sheetCount = math.max(1, value);
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Расчет по листу',
              children: [
                MetricsWrap(
                  items: [
                    MetricItem('Площадь', '${formatNumber(result.totalAreaSqm)} м²'),
                    MetricItem('Вес', '${formatNumber(result.totalWeightKg)} кг'),
                    MetricItem('Кол-во', '${model.sheetCount} шт'),
                  ],
                ),
                const Divider(height: 24),
                CostLine(label: 'Итого по листу', value: result.totalCost, emphasize: true),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SuppliersPage extends StatelessWidget {
  const SuppliersPage({super.key, required this.model});

  final EstimatorModel model;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Поставщики Липецка',
              subtitle: 'Цены можно брать из каталога или вести вручную.',
              children: [
                DropdownButtonFormField<int>(
                  value: model.selectedSupplierIndex,
                  decoration: const InputDecoration(labelText: 'Поставщик'),
                  items: [
                    for (var i = 0; i < model.suppliers.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(model.suppliers[i].name),
                      ),
                  ],
                  onChanged: (value) => value == null ? null : model.setSupplierIndex(value),
                ),
                const SizedBox(height: 12),
                Text(model.supplier.site, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(model.supplier.notes),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Использовать цены поставщика'),
                  value: model.useSupplierPrices,
                  onChanged: model.setUseSupplierPrices,
                ),
                if (!model.useSupplierPrices) ...[
                  DecimalField(
                    label: 'Цена трубы, ₽/м',
                    value: model.manualPipePricePerM,
                    onChanged: (value) {
                      model.manualPipePricePerM = value;
                      model.notify();
                    },
                  ),
                  const SizedBox(height: 12),
                  DecimalField(
                    label: 'Цена профнастила, ₽/м²',
                    value: model.manualProfSheetPricePerSqm,
                    onChanged: (value) {
                      model.manualProfSheetPricePerSqm = value;
                      model.notify();
                    },
                  ),
                  const SizedBox(height: 12),
                  DecimalField(
                    label: 'Цена листа, ₽/шт',
                    value: model.manualSheetPricePerPiece,
                    onChanged: (value) {
                      model.manualSheetPricePerPiece = value;
                      model.notify();
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Текущие цены',
              children: [
                CostLine(label: 'Труба ${model.pipe.name}', value: model.pipePricePerM),
                CostLine(label: model.profSheet.name, value: model.profSheetPricePerSqm),
                CostLine(label: sheetKindLabel(model.sheetKind), value: model.sheetPricePerPiece),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Общие настройки',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Длина хлыста, м',
                        value: model.stockLengthM,
                        onChanged: (value) {
                          model.stockLengthM = value.clamp(4, 12).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Пропил, мм',
                        value: model.sawKerfMm,
                        onChanged: (value) {
                          model.sawKerfMm = value.clamp(1, 6).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DecimalField(
                  label: 'Цена самореза, ₽',
                  value: model.fastenerPrice,
                  onChanged: (value) {
                    model.fastenerPrice = value.clamp(0, 50).toDouble();
                    model.notify();
                  },
                ),
                const SizedBox(height: 12),
                DecimalField(
                  label: 'Цена бетона, ₽/м³',
                  value: model.concretePricePerM3,
                  onChanged: (value) {
                    model.concretePricePerM3 = value.clamp(0, 30000).toDouble();
                    model.notify();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SummaryPage extends StatefulWidget {
  const SummaryPage({
    super.key,
    required this.model,
    required this.onSaveJson,
    required this.onRestoreJson,
    required this.onExportPdf,
  });

  final EstimatorModel model;
  final Future<void> Function() onSaveJson;
  final Future<void> Function() onRestoreJson;
  final Future<void> Function() onExportPdf;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool isSaving = false;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => isSaving = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        final result = model.summary;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Сохранение и экспорт',
              subtitle: 'JSON сохраняется в папку приложения. PDF содержит итоговую смету и карты раскроя.',
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: isSaving ? null : () => _guard(widget.onSaveJson),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить JSON'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: isSaving ? null : () => _guard(widget.onRestoreJson),
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Загрузить latest JSON'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: isSaving ? null : () => _guard(widget.onExportPdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Экспорт PDF'),
                    ),
                  ],
                ),
                if (isSaving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (model.lastSavedJsonPath != null) ...[
                  const SizedBox(height: 16),
                  Text('Последний JSON:\n${model.lastSavedJsonPath!}'),
                ],
                if (model.lastSavedPdfPath != null) ...[
                  const SizedBox(height: 8),
                  Text('Последний PDF:\n${model.lastSavedPdfPath!}'),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Дополнительные расходы',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Доставка, ₽',
                        value: model.deliveryCost,
                        onChanged: (value) {
                          model.deliveryCost = value.clamp(0, 1000000).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Сварка, ₽',
                        value: model.weldingCost,
                        onChanged: (value) {
                          model.weldingCost = value.clamp(0, 1000000).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DecimalField(
                        label: 'Покраска, ₽',
                        value: model.paintCost,
                        onChanged: (value) {
                          model.paintCost = value.clamp(0, 1000000).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecimalField(
                        label: 'Монтаж, ₽',
                        value: model.mountingCost,
                        onChanged: (value) {
                          model.mountingCost = value.clamp(0, 1000000).toDouble();
                          model.notify();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Итог по проекту',
              children: [
                MetricsWrap(
                  items: [
                    MetricItem('Труба', '${formatNumber(result.pipeLengthM)} м'),
                    MetricItem('Вес трубы', '${formatNumber(result.pipeWeightKg)} кг'),
                    MetricItem('Профнастил', '${formatNumber(result.profSheetPurchasedAreaSqm)} м²'),
                    MetricItem('Полос профлиста', '${result.profSheetCount} шт'),
                    MetricItem('Лист доп.', '${formatNumber(result.extraSheetAreaSqm)} м²'),
                  ],
                ),
                const Divider(height: 24),
                CostLine(label: 'Материалы', value: result.materialCost),
                CostLine(label: 'Накладные', value: result.overheadsCost),
                const Divider(height: 24),
                CostLine(label: 'Общая сумма', value: result.totalCost, emphasize: true),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Что экспортируется',
              children: const [
                Text('• параметры проекта'),
                Text('• смета по разделам'),
                Text('• карта распила трубы по хлыстам'),
                Text('• резы под 45°'),
                Text('• карта раскроя профнастила по секциям, воротам и калитке'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class PipeCutPlanCard extends StatelessWidget {
  const PipeCutPlanCard({
    super.key,
    required this.title,
    required this.stockBars,
    required this.pipePieces,
    required this.stockLengthM,
  });

  final String title;
  final List<StockBar> stockBars;
  final List<PipePiece> pipePieces;
  final double stockLengthM;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: 'Раскладка по хлыстам ${formatNumber(stockLengthM)} м c учетом пропила.',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Группа')),
              DataColumn(label: Text('Элемент')),
              DataColumn(label: Text('Длина')),
              DataColumn(label: Text('Кол-во')),
              DataColumn(label: Text('Торцы')),
            ],
            rows: [
              for (final piece in pipePieces)
                DataRow(
                  cells: [
                    DataCell(Text(piece.group)),
                    DataCell(Text(piece.label)),
                    DataCell(Text('${formatNumber(piece.lengthM)} м')),
                    DataCell(Text('${piece.quantity}')),
                    DataCell(Text(angleLabel(piece.startAngle, piece.endAngle))),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final bar in stockBars)
          ExpansionTile(
            dense: true,
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Хлыст ${bar.index} • использовано ${formatNumber(bar.usedLengthM)} м • остаток ${formatNumber(bar.wasteLengthM)} м',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in bar.items)
                      Chip(
                        label: Text('${item.label} ${formatNumber(item.lengthM)} м'),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class SheetCutPlanCard extends StatelessWidget {
  const SheetCutPlanCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.pieces,
    required this.exactAreaSqm,
    required this.purchasedAreaSqm,
  });

  final String title;
  final String? subtitle;
  final List<SheetCutPiece> pieces;
  final double exactAreaSqm;
  final double purchasedAreaSqm;

  @override
  Widget build(BuildContext context) {
    final rows = aggregateSheetPieces(pieces);
    return SectionCard(
      title: title,
      subtitle: subtitle,
      children: [
        MetricsWrap(
          items: [
            MetricItem('Полос', '${pieces.fold<int>(0, (sum, item) => sum + item.quantity)} шт'),
            MetricItem('Точно', '${formatNumber(exactAreaSqm)} м²'),
            MetricItem('Коммерч.', '${formatNumber(purchasedAreaSqm)} м²'),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Участок')),
              DataColumn(label: Text('Кол-во')),
              DataColumn(label: Text('Полезная ширина')),
              DataColumn(label: Text('Ширина реза')),
              DataColumn(label: Text('Длина листа')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(Text(row.group)),
                    DataCell(Text('${row.quantity}')),
                    DataCell(Text('${formatNumber(row.coverWidthM)} м')),
                    DataCell(Text('${formatNumber(row.actualWidthM)} м')),
                    DataCell(Text('${formatNumber(row.heightM)} м')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class MetricItem {
  const MetricItem(this.label, this.value);

  final String label;
  final String value;
}

class MetricsWrap extends StatelessWidget {
  const MetricsWrap({super.key, required this.items});

  final List<MetricItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final item in items)
          SizedBox(
            width: 168,
            child: Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CostLine extends StatelessWidget {
  const CostLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${formatMoney(value)} ₽', style: style),
        ],
      ),
    );
  }
}

class DecimalField extends StatefulWidget {
  const DecimalField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<DecimalField> createState() => _DecimalFieldState();
}

class _DecimalFieldState extends State<DecimalField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: formatNumber(widget.value));
  }

  @override
  void didUpdateWidget(covariant DecimalField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
    if (parsed == null || (parsed - widget.value).abs() > 0.0001) {
      controller.text = formatNumber(widget.value);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (value) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

class IntegerField extends StatefulWidget {
  const IntegerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<IntegerField> createState() => _IntegerFieldState();
}

class _IntegerFieldState extends State<IntegerField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant IntegerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parsed = int.tryParse(controller.text);
    if (parsed == null || parsed != widget.value) {
      controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (value) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

enum SketchKind { fence, garage }

class SketchViewer extends StatefulWidget {
  const SketchViewer({
    super.key,
    required this.kind,
    required this.length,
    required this.width,
    required this.height,
    required this.fencePosts,
    required this.roofKind,
    required this.roofAngleDeg,
  });

  final SketchKind kind;
  final double length;
  final double width;
  final double height;
  final int fencePosts;
  final RoofKind roofKind;
  final double roofAngleDeg;

  @override
  State<SketchViewer> createState() => _SketchViewerState();
}

class _SketchViewerState extends State<SketchViewer> {
  double yaw = -0.8;
  double pitch = 0.45;
  double zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          yaw += details.delta.dx * 0.01;
          pitch = (pitch - details.delta.dy * 0.01).clamp(0.1, 1.2).toDouble();
        });
      },
      onScaleUpdate: (details) {
        setState(() {
          zoom = details.scale.clamp(0.6, 2.0).toDouble();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        ),
        child: CustomPaint(
          painter: SketchPainter(
            kind: widget.kind,
            length: widget.length,
            width: widget.width,
            height: widget.height,
            fencePosts: widget.fencePosts,
            roofKind: widget.roofKind,
            roofAngleDeg: widget.roofAngleDeg,
            yaw: yaw,
            pitch: pitch,
            zoom: zoom,
            colorScheme: Theme.of(context).colorScheme,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class SketchPainter extends CustomPainter {
  SketchPainter({
    required this.kind,
    required this.length,
    required this.width,
    required this.height,
    required this.fencePosts,
    required this.roofKind,
    required this.roofAngleDeg,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.colorScheme,
  });

  final SketchKind kind;
  final double length;
  final double width;
  final double height;
  final int fencePosts;
  final RoofKind roofKind;
  final double roofAngleDeg;
  final double yaw;
  final double pitch;
  final double zoom;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final framePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = colorScheme.secondary.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final profPaint = Paint()
      ..color = colorScheme.tertiary.withOpacity(0.22)
      ..style = PaintingStyle.fill;

    final guidePaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;

    canvas.translate(size.width / 2, size.height / 2 + 40);
    final scale = (size.shortestSide / (kind == SketchKind.fence ? 14 : 10)) * zoom;

    for (double i = -size.width; i < size.width; i += 30) {
      canvas.drawLine(
        Offset(i, size.height / 2),
        Offset(i + size.width, -size.height / 2),
        guidePaint,
      );
    }

    if (kind == SketchKind.fence) {
      _drawFence(canvas, framePaint, profPaint, scale);
    } else {
      _drawGarage(canvas, framePaint, fillPaint, profPaint, scale);
    }
  }

  void _drawFence(Canvas canvas, Paint framePaint, Paint profPaint, double scale) {
    final visualLength = math.max(4.0, length / 2.5);
    final visualHeight = math.max(1.8, height);
    final postVisualCount = math.max(2, fencePosts);

    final bottomA = _project(Point3(-visualLength / 2, 0, 0), scale);
    final bottomB = _project(Point3(visualLength / 2, 0, 0), scale);
    final topA = _project(Point3(-visualLength / 2, 0, visualHeight), scale);
    final topB = _project(Point3(visualLength / 2, 0, visualHeight), scale);

    final sheetRect = Path()
      ..moveTo(bottomA.dx, bottomA.dy)
      ..lineTo(bottomB.dx, bottomB.dy)
      ..lineTo(topB.dx, topB.dy)
      ..lineTo(topA.dx, topA.dy)
      ..close();

    canvas.drawPath(sheetRect, profPaint);
    canvas.drawLine(bottomA, bottomB, framePaint);
    canvas.drawLine(topA, topB, framePaint);
    canvas.drawLine(bottomA, topA, framePaint);
    canvas.drawLine(bottomB, topB, framePaint);

    for (var i = 0; i < postVisualCount; i++) {
      final t = postVisualCount == 1 ? 0.0 : i / (postVisualCount - 1);
      final x = -visualLength / 2 + visualLength * t;
      final p1 = _project(Point3(x, 0, 0), scale);
      final p2 = _project(Point3(x, 0, visualHeight + 0.6), scale);
      canvas.drawLine(p1, p2, framePaint);
    }

    final rail1A = _project(Point3(-visualLength / 2, 0, visualHeight * 0.33), scale);
    final rail1B = _project(Point3(visualLength / 2, 0, visualHeight * 0.33), scale);
    final rail2A = _project(Point3(-visualLength / 2, 0, visualHeight * 0.66), scale);
    final rail2B = _project(Point3(visualLength / 2, 0, visualHeight * 0.66), scale);
    canvas.drawLine(rail1A, rail1B, framePaint);
    canvas.drawLine(rail2A, rail2B, framePaint);
  }

  void _drawGarage(
    Canvas canvas,
    Paint framePaint,
    Paint fillPaint,
    Paint profPaint,
    double scale,
  ) {
    final l = math.max(4.0, length);
    final w = math.max(3.0, width);
    final h = math.max(2.2, height);
    final rad = roofAngleDeg * math.pi / 180;
    final rise = roofKind == RoofKind.singleSlope ? w * math.tan(rad) : (w / 2) * math.tan(rad);

    final pts = <String, Point3>{
      'A': Point3(-l / 2, -w / 2, 0),
      'B': Point3(l / 2, -w / 2, 0),
      'C': Point3(l / 2, w / 2, 0),
      'D': Point3(-l / 2, w / 2, 0),
      'E': Point3(-l / 2, -w / 2, h),
      'F': Point3(l / 2, -w / 2, h),
      'G': Point3(l / 2, w / 2, h),
      'H': Point3(-l / 2, w / 2, h),
    };

    if (roofKind == RoofKind.singleSlope) {
      pts['G'] = Point3(l / 2, w / 2, h + rise);
      pts['H'] = Point3(-l / 2, w / 2, h + rise);
    }

    final roofPeakLeft = Point3(-l / 2, 0, h + rise);
    final roofPeakRight = Point3(l / 2, 0, h + rise);

    final wallPath = Path()
      ..moveTo(_project(pts['A']!, scale).dx, _project(pts['A']!, scale).dy)
      ..lineTo(_project(pts['B']!, scale).dx, _project(pts['B']!, scale).dy)
      ..lineTo(_project(pts['F']!, scale).dx, _project(pts['F']!, scale).dy)
      ..lineTo(_project(pts['E']!, scale).dx, _project(pts['E']!, scale).dy)
      ..close();

    final sidePath = Path()
      ..moveTo(_project(pts['B']!, scale).dx, _project(pts['B']!, scale).dy)
      ..lineTo(_project(pts['C']!, scale).dx, _project(pts['C']!, scale).dy)
      ..lineTo(_project(pts['G']!, scale).dx, _project(pts['G']!, scale).dy)
      ..lineTo(_project(pts['F']!, scale).dx, _project(pts['F']!, scale).dy)
      ..close();

    canvas.drawPath(wallPath, fillPaint);
    canvas.drawPath(sidePath, profPaint);

    _edge(canvas, framePaint, pts['A']!, pts['B']!, scale);
    _edge(canvas, framePaint, pts['B']!, pts['C']!, scale);
    _edge(canvas, framePaint, pts['C']!, pts['D']!, scale);
    _edge(canvas, framePaint, pts['D']!, pts['A']!, scale);

    if (roofKind == RoofKind.singleSlope) {
      _edge(canvas, framePaint, pts['E']!, pts['F']!, scale);
      _edge(canvas, framePaint, pts['F']!, pts['G']!, scale);
      _edge(canvas, framePaint, pts['G']!, pts['H']!, scale);
      _edge(canvas, framePaint, pts['H']!, pts['E']!, scale);
    } else {
      _edge(canvas, framePaint, pts['E']!, roofPeakLeft, scale);
      _edge(canvas, framePaint, pts['H']!, roofPeakLeft, scale);
      _edge(canvas, framePaint, pts['F']!, roofPeakRight, scale);
      _edge(canvas, framePaint, pts['G']!, roofPeakRight, scale);
      _edge(canvas, framePaint, roofPeakLeft, roofPeakRight, scale);
    }

    _edge(canvas, framePaint, pts['A']!, pts['E']!, scale);
    _edge(canvas, framePaint, pts['B']!, pts['F']!, scale);
    _edge(canvas, framePaint, pts['C']!, pts['G']!, scale);
    _edge(canvas, framePaint, pts['D']!, pts['H']!, scale);

    final gateW = l * 0.45;
    final gateH = h * 0.78;
    final gate = [
      _project(Point3(-gateW / 2, -w / 2, 0), scale),
      _project(Point3(gateW / 2, -w / 2, 0), scale),
      _project(Point3(gateW / 2, -w / 2, gateH), scale),
      _project(Point3(-gateW / 2, -w / 2, gateH), scale),
    ];
    canvas.drawPath(
      Path()
        ..moveTo(gate[0].dx, gate[0].dy)
        ..lineTo(gate[1].dx, gate[1].dy)
        ..lineTo(gate[2].dx, gate[2].dy)
        ..lineTo(gate[3].dx, gate[3].dy)
        ..close(),
      framePaint,
    );
  }

  void _edge(Canvas canvas, Paint paint, Point3 a, Point3 b, double scale) {
    canvas.drawLine(_project(a, scale), _project(b, scale), paint);
  }

  Offset _project(Point3 p, double scale) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);

    final x1 = p.x * cy - p.y * sy;
    final y1 = p.x * sy + p.y * cy;
    final z1 = p.z;

    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;

    return Offset(x1 * scale, (-y2 - z2 * 0.15) * scale);
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) {
    return yaw != oldDelegate.yaw ||
        pitch != oldDelegate.pitch ||
        zoom != oldDelegate.zoom ||
        length != oldDelegate.length ||
        width != oldDelegate.width ||
        height != oldDelegate.height ||
        fencePosts != oldDelegate.fencePosts ||
        roofKind != oldDelegate.roofKind ||
        roofAngleDeg != oldDelegate.roofAngleDeg ||
        kind != oldDelegate.kind;
  }
}

class Point3 {
  const Point3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class ProjectNameField extends StatefulWidget {
  const ProjectNameField({super.key, required this.model});

  final EstimatorModel model;

  @override
  State<ProjectNameField> createState() => _ProjectNameFieldState();
}

class _ProjectNameFieldState extends State<ProjectNameField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.model.projectName);
  }

  @override
  void didUpdateWidget(covariant ProjectNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.model.projectName) {
      controller.text = widget.model.projectName;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: const InputDecoration(labelText: 'Название проекта'),
      onChanged: (value) {
        widget.model.projectName = value.isEmpty ? 'МеталлСмета 48' : value;
        widget.model.notify();
      },
    );
  }
}

String angleLabel(CutAngle start, CutAngle end) {
  final startLabel = start == CutAngle.miter45 ? '45°' : '90°';
  final endLabel = end == CutAngle.miter45 ? '45°' : '90°';
  return '$startLabel / $endLabel';
}

String formatNumber(double value) {
  final fixed = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  return fixed.replaceAll(RegExp(r'\.?0+$'), '');
}

String formatMoney(double value) {
  final sign = value < 0 ? '-' : '';
  final text = value.abs().round().toString();
  final buffer = StringBuffer(sign);
  for (var i = 0; i < text.length; i++) {
    final reverseIndex = text.length - i;
    buffer.write(text[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write(' ');
    }
  }
  return buffer.toString();
}

String sheetKindLabel(SheetKind kind) {
  switch (kind) {
    case SheetKind.hotRolled:
      return 'Г/к лист';
    case SheetKind.coldRolled:
      return 'Х/к лист';
    case SheetKind.galvanized:
      return 'Оцинкованный лист';
  }
}

String _timestampForFile() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

pw.Widget _pdfCell(String value, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(_asciiSafe(value), style: style),
  );
}


String _asciiSafe(String value) {
  final map = <String, String>{
    'А': 'A', 'а': 'a', 'Б': 'B', 'б': 'b', 'В': 'V', 'в': 'v', 'Г': 'G', 'г': 'g',
    'Д': 'D', 'д': 'd', 'Е': 'E', 'е': 'e', 'Ё': 'E', 'ё': 'e', 'Ж': 'Zh', 'ж': 'zh',
    'З': 'Z', 'з': 'z', 'И': 'I', 'и': 'i', 'Й': 'Y', 'й': 'y', 'К': 'K', 'к': 'k',
    'Л': 'L', 'л': 'l', 'М': 'M', 'м': 'm', 'Н': 'N', 'н': 'n', 'О': 'O', 'о': 'o',
    'П': 'P', 'п': 'p', 'Р': 'R', 'р': 'r', 'С': 'S', 'с': 's', 'Т': 'T', 'т': 't',
    'У': 'U', 'у': 'u', 'Ф': 'F', 'ф': 'f', 'Х': 'Kh', 'х': 'kh', 'Ц': 'Ts', 'ц': 'ts',
    'Ч': 'Ch', 'ч': 'ch', 'Ш': 'Sh', 'ш': 'sh', 'Щ': 'Sch', 'щ': 'sch', 'Ъ': '', 'ъ': '',
    'Ы': 'Y', 'ы': 'y', 'Ь': '', 'ь': '', 'Э': 'E', 'э': 'e', 'Ю': 'Yu', 'ю': 'yu',
    'Я': 'Ya', 'я': 'ya', '№': 'No.', '₽': 'RUB',
  };
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}
