class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  static const supported = ['en', 'hi', 'ar'];

  static AppStrings of(String code) => AppStrings(supported.contains(code) ? code : 'en');

  String _t(String key) => _data[languageCode]?[key] ?? _data['en']![key] ?? key;

  String tr(String key, {Map<String, String>? args}) {
    var text = _t(key);
    if (args != null) {
      for (final entry in args.entries) {
        text = text.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return text;
  }

  String get settings => _t('settings');
  String get product => _t('product');
  String get inventory => _t('inventory');
  String get search => _t('search');
  String get order => _t('order');
  String get stockTransfer => _t('stockTransfer');
  String get report => _t('report');
  String get quotations => _t('quotations');
  String get deliveryChallan => _t('deliveryChallan');
  String get labelTodayRate => _t('labelTodayRate');
  String get sampleIn => _t('sampleIn');
  String get sampleOut => _t('sampleOut');
  String get home => _t('home');
  String get logout => _t('logout');
  String get account => _t('account');
  String get usernamePassword => _t('usernamePassword');
  String get userPermission => _t('userPermission');
  String get managePermission => _t('managePermission');
  String get email => _t('email');
  String get backup => _t('backup');
  String get dataBackup => _t('dataBackup');
  String get autoSync => _t('autoSync');
  String get enableAutomaticSync => _t('enableAutomaticSync');
  String get notifications => _t('notifications');
  String get notificationSettings => _t('notificationSettings');
  String get branches => _t('branches');
  String get branchManagement => _t('branchManagement');
  String get customApi => _t('customApi');
  String get configureApiUrl => _t('configureApiUrl');
  String get sheetUrl => _t('sheetUrl');
  String get setGoogleSheetUrl => _t('setGoogleSheetUrl');
  String get stockTransferUrl => _t('stockTransferUrl');
  String get stockTransferApiUrl => _t('stockTransferApiUrl');
  String get clearData => _t('clearData');
  String get clearLocalData => _t('clearLocalData');
  String get language => _t('language');
  String get location => _t('location');
  String get selectLanguage => _t('selectLanguage');
  String get english => _t('english');
  String get hindi => _t('hindi');
  String get arabic => _t('arabic');
  String get locationList => _t('locationList');
  String get selectDate => _t('selectDate');
  String get headerSr => _t('headerSr');
  String get date => _t('date');
  String get userId => _t('userId');
  String get address => _t('address');
  String get noLocationsFound => _t('noLocationsFound');
  String get failedToGetLocation => _t('failedToGetLocation');
  String get back => _t('back');
  String get cancel => _t('cancel');
  String get save => _t('save');
  String get ok => _t('ok');
  String get route => _t('route');
  String get defaultLoginEmail => _t('defaultLoginEmail');
  String get permissionsFromServer => _t('permissionsFromServer');
  String get backupOptions => _t('backupOptions');
  String get backupChoose => _t('backupChoose');
  String get saveToDevice => _t('saveToDevice');
  String get sendViaEmail => _t('sendViaEmail');
  String get restoreBackup => _t('restoreBackup');
  String get autoSyncSettings => _t('autoSyncSettings');
  String get syncInterval => _t('syncInterval');
  String get min15 => _t('min15');
  String get min30 => _t('min30');
  String get hour1 => _t('hour1');
  String get hour24 => _t('hour24');
  String get confirmClearData => _t('confirmClearData');
  String get clearDataMessage => _t('clearDataMessage');
  String get continueLabel => _t('continueLabel');
  String get verifyPassword => _t('verifyPassword');
  String get password => _t('password');
  String get incorrectPassword => _t('incorrectPassword');
  String get enableNotifications => _t('enableNotifications');
  String get usernameLabel => _t('usernameLabel');
  String get send => _t('send');
  String get restoreComplete => _t('restoreComplete');
  String get backupFailed => _t('backupFailed');
  String get savedTo => _t('savedTo');
  String get selectedBranchIds => _t('selectedBranchIds');
  String get enterEmailAddress => _t('enterEmailAddress');
  String get clearBtn => _t('clearBtn');
  String get viewLocationList => _t('viewLocationList');
  String get enabled => _t('enabled');
  String get disabled => _t('disabled');
  String get configureCustomApi => _t('configureCustomApi');
  String get apiUrlAuthorizedMessage => _t('apiUrlAuthorizedMessage');
  String get enterApiUrl => _t('enterApiUrl');
  String get customApiSaved => _t('customApiSaved');
  String get expiryWarning => _t('expiryWarning');
  String get welcomeTo => _t('welcomeTo');
  String get sparkleRfid => _t('sparkleRfid');
  String get pleaseLoginToContinue => _t('pleaseLoginToContinue');
  String get rememberMe => _t('rememberMe');
  String get forgotPassword => _t('forgotPassword');
  String get useFaceDetectionLogin => _t('useFaceDetectionLogin');
  String get logIn => _t('logIn');
  String get logInWithFace => _t('logInWithFace');
  String get troubleLogin => _t('troubleLogin');
  String get contactUsClicked => _t('contactUsClicked');
  String get contactUs => _t('contactUs');
  String get faceScanSimulationComplete => _t('faceScanSimulationComplete');
  String get faceLogin => _t('faceLogin');
  String get alignFaceInCircle => _t('alignFaceInCircle');
  String get scanningFace => _t('scanningFace');
  String get scanDisplay => _t('scanDisplay');
  String get scanCounter => _t('scanCounter');
  String get scanBox => _t('scanBox');
  String get scanBranch => _t('scanBranch');
  String get exhibition => _t('exhibition');
  String get noCountersFound => _t('noCountersFound');
  String get noBoxesFound => _t('noBoxesFound');
  String get noBranchesFound => _t('noBranchesFound');
  String get noExhibitionsFound => _t('noExhibitionsFound');
  String get counter => _t('counter');
  String get box => _t('box');
  String get branch => _t('branch');
  String get addSingleProduct => _t('addSingleProduct');
  String get addBulkProducts => _t('addBulkProducts');
  String get importExcel => _t('importExcel');
  String get exportExcel => _t('exportExcel');
  String get syncData => _t('syncData');
  String get scanToDesktop => _t('scanToDesktop');
  String get syncSheetData => _t('syncSheetData');
  String get uploadDataToServer => _t('uploadDataToServer');
  String get noLocalDataToExport => _t('noLocalDataToExport');
  String get openProductList => _t('openProductList');
  String get exportingExcel => _t('exportingExcel');
  String get dataSyncSuccess => _t('dataSyncSuccess');
  String get showLess => _t('showLess');
  String get done => _t('done');
  String get user => _t('user');
  String get comingSoon => _t('comingSoon');
  String get failedToStartRfidScanner => _t('failedToStartRfidScanner');
  String get delete => _t('delete');
  String get reset => _t('reset');
  String get apply => _t('apply');
  String get productName => _t('productName');
  String get itemCode => _t('itemCode');
  String get itemDetails => _t('itemDetails');
  String get rfidCode => _t('rfidCode');
  String get pleaseSelectSampleOutNoFirst => _t('pleaseSelectSampleOutNoFirst');
  String get customerProfile => _t('customerProfile');
  String get customerAddedSuccessfully => _t('customerAddedSuccessfully');
  String get customerAddedOffline => _t('customerAddedOffline');
  String get errorAddingCustomer => _t('errorAddingCustomer');
  String get confirmMatch => _t('confirmMatch');
  String get confirmAddToMatchedList => _t('confirmAddToMatchedList');
  String get labelNo => _t('labelNo');
  String get labelYes => _t('labelYes');
  String get itemAddedToMatchedList => _t('itemAddedToMatchedList');
  String get removeMatch => _t('removeMatch');
  String get confirmRemoveFromMatchedList => _t('confirmRemoveFromMatchedList');
  String get enterCustomerName => _t('enterCustomerName');
  String get selectCustomerFirst => _t('selectCustomerFirst');
  String get enterSampleOutNo => _t('enterSampleOutNo');
  String get sampleInSavedSuccessfully => _t('sampleInSavedSuccessfully');
  String get failedToSaveSampleIn => _t('failedToSaveSampleIn');
  String get sampleInList => _t('sampleInList');
  String get searchSoNoCustomerProduct => _t('searchSoNoCustomerProduct');
  String get noSampleInRecordsFound => _t('noSampleInRecordsFound');
  String get headerSoNo => _t('headerSoNo');
  String get headerCustName => _t('headerCustName');
  String get headerRDate => _t('headerRDate');
  String get headerPName => _t('headerPName');
  String get headerTWt => _t('headerTWt');
  String get headerGwt => _t('headerGwt');
  String get headerSwt => _t('headerSwt');
  String get headerDwt => _t('headerDwt');
  String get headerQty => _t('headerQty');
  String get description => _t('description');
  String get deleteItem => _t('deleteItem');
  String get removeItemFromSampleOut => _t('removeItemFromSampleOut');
  String get enterRfidItemcode => _t('enterRfidItemcode');
  String get sampleOutFields => _t('sampleOutFields');
  String get unknown => _t('unknown');
  String get editSampleOut => _t('editSampleOut');
  String get createSampleOut => _t('createSampleOut');
  String get rfidPower => _t('rfidPower');
  String get noItemsAdded => _t('noItemsAdded');
  String get headerSno => _t('headerSno');
  String get total => _t('total');
  String get action => _t('action');
  String get sampleOutUpdatedSuccessfully => _t('sampleOutUpdatedSuccessfully');
  String get failedToUpdateSampleOut => _t('failedToUpdateSampleOut');
  String get sampleOutSavedSuccessfully => _t('sampleOutSavedSuccessfully');
  String get failedToSaveSampleOut => _t('failedToSaveSampleOut');
  String get sampleOutList => _t('sampleOutList');
  String get searchSampleOutNoCustomer => _t('searchSampleOutNoCustomer');
  String get noSampleOutRecordsFound => _t('noSampleOutRecordsFound');
  String get createSampleOutHint => _t('createSampleOutHint');
  String get headerCustomer => _t('headerCustomer');
  String get headerReturn => _t('headerReturn');
  String get selectSampleOutNoToLoadItems => _t('selectSampleOutNoToLoadItems');
  String get status => _t('status');
  String get headerPcs => _t('headerPcs');
  String get headerFwWt => _t('headerFwWt');
  String get headerNwt => _t('headerNwt');
  String get returnLabel => _t('returnLabel');
  String get nonReturn => _t('nonReturn');
  String get returnDate => _t('returnDate');
  String get enterDescription => _t('enterDescription');
  String get confirm => _t('confirm');
  String get listBtn => _t('listBtn');
  String get scanBtn => _t('scanBtn');
  String get stop => _t('stop');
  String get gscan => _t('gscan');
  String get update => _t('update');
  String get transfer => _t('transfer');
  String get stockVerificationReport => _t('stockVerificationReport');
  String get reportExportedSuccessfully => _t('reportExportedSuccessfully');
  String get errorLoadingSessions => _t('errorLoadingSessions');
  String get noSessionsFound => _t('noSessionsFound');
  String get errorLoadingReport => _t('errorLoadingReport');
  String get noDataForSelectedDate => _t('noDataForSelectedDate');
  String get batchWise => _t('batchWise');
  String get consolidated => _t('consolidated');
  String get filter => _t('filter');
  String get allBranches => _t('allBranches');
  String get fromDate => _t('fromDate');
  String get toDate => _t('toDate');
  String get errorLoadingData => _t('errorLoadingData');
  String get noItemsFound => _t('noItemsFound');
  String get headerItem => _t('headerItem');
  String get headerRfid => _t('headerRfid');
  String get headerCategory => _t('fieldCategory');
  String get headerGrossWt => _t('colGrossWt');
  String get headerNetWt => _t('colNetWt');
  String get headerStoneWt => _t('colStoneWt');
  String get headerDiamondWt => _t('colDiamondWt');
  String get headerStatus => _t('status');
  String get batchDetails => _t('batchDetails');
  String get searchItemProductRfidCategory => _t('searchItemProductRfidCategory');
  String get matchedItems => _t('matchedItems');
  String get unmatchedItems => _t('unmatchedItems');
  String get noItems => _t('noItems');
  String get headerItemCode => _t('itemCode');
  String get notAvailable => _t('notAvailable');
  String get localServerRunning => _t('localServerRunning');
  String get localServerStopped => _t('localServerStopped');
  String get desktopUrl => _t('desktopUrl');
  String get urlCopiedToClipboard => _t('urlCopiedToClipboard');
  String get noTagsScannedYet => _t('noTagsScannedYet');
  String get totalScanned => _t('totalScanned');
  String get scannedTagsCleared => _t('scannedTagsCleared');
  String get scanResetSuccessful => _t('scanResetSuccessful');
  String get assignRfidCode => _t('assignRfidCode');
  String get assign => _t('assign');
  String get scannedTagsSavedToDesktop => _t('scannedTagsSavedToDesktop');
  String get scanHere => _t('scanHere');
  String get loadingEllipsis => _t('loadingEllipsis');
  String get searchUnmatched => _t('searchUnmatched');
  String get searchAllItems => _t('searchAllItems');
  String get searchType => _t('searchType');
  String get labelStock => _t('labelStock');
  String get enterRfidCustomOrderId => _t('enterRfidCustomOrderId');
  String get enterRfidBoxRfid => _t('enterRfidBoxRfid');
  String get srNo => _t('srNo');
  String get progress => _t('progress');
  String get percent => _t('percent');
  String get noUnmatchedItemsToSearch => _t('noUnmatchedItemsToSearch');
  String get typeRfidItemcodeToSearch => _t('typeRfidItemcodeToSearch');
  String get noItemsToSearch => _t('noItemsToSearch');
  String get noSearchableIdentifiers => _t('noSearchableIdentifiers');
  String get searchItemRfidProduct => _t('searchItemRfidProduct');
  String get category => _t('fieldCategory');
  String get design => _t('fieldDesign');
  String get qty => _t('qty');
  String get mQty => _t('mQty');
  String get mWt => _t('mWt');
  String get grossWt => _t('grossWt');
  String get rfidNo => _t('rfidNo');
  String get itemcode => _t('itemcode');
  String get matchedItemsMenu => _t('matchedItemsMenu');
  String get unmatchedItemsMenu => _t('unmatchedItemsMenu');
  String get unlabelledItems => _t('unlabelledItems');
  String get resumeScan => _t('resumeScan');
  String get searchUnmatchedMenu => _t('searchUnmatchedMenu');
  String get noItemsFoundUnderScope => _t('noItemsFoundUnderScope');
  String get allItemsMatchedScanStopped => _t('allItemsMatchedScanStopped');
  String get pleaseWaitItemsLoading => _t('pleaseWaitItemsLoading');
  String get noItemsInCurrentScope => _t('noItemsInCurrentScope');
  String get noRfidEpcInScope => _t('noRfidEpcInScope');
  String get allItemsAlreadyMatched => _t('allItemsAlreadyMatched');
  String get previousScanRestored => _t('previousScanRestored');
  String get errorSessionExpired => _t('errorSessionExpired');
  String get stockVerificationUploaded => _t('stockVerificationUploaded');
  String get sendReport => _t('sendReport');
  String get savedEmails => _t('savedEmails');
  String get pleaseEnterOrSelectEmail => _t('pleaseEnterOrSelectEmail');
  String get pleaseEnterValidEmail => _t('pleaseEnterValidEmail');
  String get failedToSendEmail => _t('failedToSendEmail');
  String get inventoryScanReportSubject => _t('inventoryScanReportSubject');
  String get searchProductRfidEpc => _t('searchProductRfidEpc');
  String get purity => _t('fieldPurity');
  String get error => _t('error');
  String get customerOrdersList => _t('customerOrdersList');
  String get deleteOrder => _t('deleteOrder');
  String get deleteOrderConfirm => _t('deleteOrderConfirm');
  String get searchOrderHint => _t('searchOrderHint');
  String get orderDeletedSuccessfully => _t('orderDeletedSuccessfully');
  String get deliveryChallanList => _t('deliveryChallanList');
  String get searchChallanHint => _t('searchChallanHint');
  String get noChallansFound => _t('noChallansFound');
  String get confirmDeleteChallan => _t('confirmDeleteChallan');
  String get challanDeletedSuccessfully => _t('challanDeletedSuccessfully');
  String get noOrdersFound => _t('noOrdersFound');
  String get walkInCustomer => _t('walkInCustomer');
  String get headerOrderNo => _t('headerOrderNo');
  String get headerFineWt => _t('headerFineWt');
  String get headerTaxAmt => _t('headerTaxAmt');
  String get headerTotalAmt => _t('headerTotalAmt');
  String get createChallanHint => _t('createChallanHint');
  String get headerChallanNo => _t('headerChallanNo');

  String get lblRfid => _t('lblRfid');
  String get lblCode => _t('lblCode');
  String get lblGrossWt => _t('lblGrossWt');
  String get lblNetWt => _t('lblNetWt');
  String get lblStoneWt => _t('lblStoneWt');
  String get lblDiamondWt => _t('lblDiamondWt');

  String get colGrossWt => _t('colGrossWt');
  String get colStoneWt => _t('colStoneWt');
  String get colDiamondWt => _t('colDiamondWt');
  String get colNetWt => _t('colNetWt');
  String get colStoneAmt => _t('colStoneAmt');
  String get colDiamondAmt => _t('colDiamondAmt');
  String get colRfid => _t('colRfid');
  String get colSku => _t('colSku');
  String get colEpc => _t('colEpc');
  String get colVendor => _t('colVendor');

  String get localWebServerRunning => _t('localWebServerRunning');
  String get localWebServerStopped => _t('localWebServerStopped');

  String get fieldCategory => _t('fieldCategory');
  String get fieldProduct => _t('fieldProduct');
  String get fieldDesign => _t('fieldDesign');
  String get fieldPurity => _t('fieldPurity');
  String get fieldGrossWeight => _t('fieldGrossWeight');
  String get fieldStoneWeight => _t('fieldStoneWeight');
  String get fieldDiamondWeight => _t('fieldDiamondWeight');
  String get fieldNetWeight => _t('fieldNetWeight');
  String get fieldMakingGram => _t('fieldMakingGram');
  String get fieldMakingPercent => _t('fieldMakingPercent');
  String get fieldFixMaking => _t('fieldFixMaking');
  String get fieldFixWastage => _t('fieldFixWastage');
  String get fieldStoneAmount => _t('fieldStoneAmount');
  String get fieldDiamondAmount => _t('fieldDiamondAmount');

  String get fieldVendor => _t('fieldVendor');
  String get fieldSku => _t('fieldSku');
  String get fieldRfidCode => _t('fieldRfidCode');

  String get reportEmailBody => _t('reportEmailBody');
  String get actions => _t('actions');
  String get all => _t('all');
  String get loading => _t('loading');

  String totalScannedCount(dynamic count) => _t('totalScanned').replaceAll('{count}', '$count');

  String get exporting => _t('exporting');
  String get exportPdf => _t('exportPdf');
  String get gridView => _t('gridView');
  String get filters => _t('filters');
  String get listView => _t('listView');
  String get searchSkuCodeName => _t('searchSkuCodeName');

  String errorGeneratingPdf(dynamic error) => _t('errorGeneratingPdf').replaceAll('{error}', '$error');
  String productListCount(dynamic count) => _t('productListCount').replaceAll('{count}', '$count');
  String totalItems(dynamic count) => _t('totalItems').replaceAll('{count}', '$count');
  String pageOf(dynamic page, dynamic total) => _t('pageOf').replaceAll('{page}', '$page').replaceAll('{total}', '$total');
  String errorWithMessage(dynamic message) => _t('errorWithMessage').replaceAll('{message}', '$message');

  String get addAtLeastOneItem => _t('addAtLeastOneItem');
  String get orderScreen => _t('orderScreen');
  String get orderDetails => _t('orderDetails');
  String get itemAmt => _t('itemAmt');
  String get confirmDeleteItem => _t('confirmDeleteItem');
  String get gstLabel => _t('gstLabel');
  String get totalAmount => _t('totalAmount');
  String get orderSavedSuccessfully => _t('orderSavedSuccessfully');
  String get orderSavedOffline => _t('orderSavedOffline');
  String get orderPendingSync => _t('orderPendingSync');
  String get syncOrdersNow => _t('syncOrdersNow');
  String get offlineOrderMode => _t('offlineOrderMode');
  String get failedToSaveOrder => _t('failedToSaveOrder');

  String get confirmDeleteChallanItem => _t('confirmDeleteChallanItem');
  String get challanFields => _t('challanFields');
  String get itemName => _t('itemName');
  String get rate => _t('rate');
  String get makingChg => _t('makingChg');
  String get amount => _t('amount');
  String get fineWt => _t('fineWt');
  String get editDeliveryChallan => _t('editDeliveryChallan');
  String get createDeliveryChallan => _t('createDeliveryChallan');
  String get challanSavedSuccessfully => _t('challanSavedSuccessfully');
  String get challanUpdatedSuccessfully => _t('challanUpdatedSuccessfully');
  String get failedToSubmitChallan => _t('failedToSubmitChallan');

  String get quotationList => _t('quotationList');
  String get searchQuotationHint => _t('searchQuotationHint');
  String get noQuotationsFound => _t('noQuotationsFound');
  String get headerQNo => _t('headerQNo');
  String get customerName => _t('customerName');

  String get addAtLeastOneQuotationItem => _t('addAtLeastOneQuotationItem');
  String get quotationDetails => _t('quotationDetails');
  String get quotationSavedSuccessfully => _t('quotationSavedSuccessfully');
  String get quotationUpdatedSuccessfully => _t('quotationUpdatedSuccessfully');
  String get failedToSaveQuotation => _t('failedToSaveQuotation');

  String get ratesUpdatedSuccessfully => _t('ratesUpdatedSuccessfully');
  String get failedToUpdateRates => _t('failedToUpdateRates');
  String get noRatesFound => _t('noRatesFound');
  String get todayRatePerGm => _t('todayRatePerGm');

  String searchError(dynamic error) => _t('searchError').replaceAll('{error}', '$error');
  String get noSearchableIdentifiersFound => _t('noSearchableIdentifiersFound');

  String get searchSampleOutHint => _t('searchSampleOutHint');
  String get returnTitle => _t('returnTitle');
  String get selectSampleOutNoFirst => _t('selectSampleOutNoFirst');
  String get confirmAddMatched => _t('confirmAddMatched');
  String get no => _t('no');
  String get yes => _t('yes');
  String get itemAddedInMatchedList => _t('itemAddedInMatchedList');
  String get confirmRemoveMatched => _t('confirmRemoveMatched');
  String get itemsLabel => _t('itemsLabel');

  String exportingProgress(dynamic count) => _t('exportingProgress').replaceAll('{count}', '$count');

  String get noProductsToExport => _t('noProductsToExport');
  String get labelledStockReport => _t('labelledStockReport');
  String get noProductsMatchingFilters => _t('noProductsMatchingFilters');
  String get tryResettingFilters => _t('tryResettingFilters');
  String get apiActiveCannotEdit => _t('apiActiveCannotEdit');
  String get generalDetails => _t('generalDetails');
  String get productTitleName => _t('productTitleName');
  String get nameRequired => _t('nameRequired');
  String get pieces => _t('pieces');
  String get weights => _t('weights');
  String get grossWeightG => _t('grossWeightG');
  String get netWeightG => _t('netWeightG');
  String get stoneWeightG => _t('stoneWeightG');
  String get diamondWeightG => _t('diamondWeightG');
  String get makingStonePricing => _t('makingStonePricing');
  String get makingPerGram => _t('makingPerGram');
  String get rfidStoreDetails => _t('rfidStoreDetails');
  String get rfidTag => _t('rfidTag');
  String get epcValueUhf => _t('epcValueUhf');
  String get skuCode => _t('skuCode');
  String get branchName => _t('branchName');
  String get boxName => _t('boxName');
  String get failedToUpdateProduct => _t('failedToUpdateProduct');
  String get productUpdatedSuccessfully => _t('productUpdatedSuccessfully');
  String get deleteProduct => _t('deleteProduct');
  String get productDeletedSuccessfully => _t('productDeletedSuccessfully');
  String get editProduct => _t('editProduct');
  String get saveDetails => _t('saveDetails');

  String get customOrderFields => _t('customOrderFields');
  String get totalWeight => _t('totalWeight');
  String get packingWt => _t('packingWt');
  String get ratePerGram => _t('ratePerGram');
  String get colors => _t('colors');
  String get screwType => _t('screwType');
  String get polishType => _t('polishType');
  String get finePercent => _t('finePercent');
  String get wastagePercent => _t('wastagePercent');
  String get deliveryDate => _t('deliveryDate');
  String get mrp => _t('mrp');
  String get colorType => _t('colorType');
  String get selectBranch => _t('selectBranch');
  String get salesman => _t('salesman');
  String get pleaseSelectBranchAndDate => _t('pleaseSelectBranchAndDate');
  String get orderDate => _t('orderDate');

  String get size => _t('size');
  String get length => _t('length');
  String get hallmarkAmt => _t('hallmarkAmt');
  String get finePlusWt => _t('finePlusWt');
  String get remark => _t('remark');
  String get matched => _t('matched');
  String get unmatched => _t('unmatched');

  String get tapToEnter => _t('tapToEnter');
  String get categoryFirst => _t('categoryFirst');
  String get productFirst => _t('productFirst');
  String get designFirst => _t('designFirst');
  String get selectVendorFirst => _t('selectVendorFirst');
  String get retry => _t('retry');
  String get select => _t('select');
  String get tableView => _t('tableView');
  String get selectTableViewFields => _t('selectTableViewFields');
  String get mainFields => _t('mainFields');
  String get selectSheetFields => _t('selectSheetFields');
  String get mapColumn => _t('mapColumn');
  String get import => _t('import');
  String get item => _t('item');
  String get tapTo => _t('tapTo');
  String get chooseFile => _t('chooseFile');
  String get formatsLabel => _t('formatsLabel');
  String get maxFileSize => _t('maxFileSize');

  String get totalInv => _t('totalInv');
  String get start => _t('start');
  String get end => _t('end');
  String get totalQty => _t('totalQty');
  String get match => _t('match');
  String get unmatch => _t('unmatch');

  String get privacyPolicy => _t('privacyPolicy');
  String get viewPrivacyPolicy => _t('viewPrivacyPolicy');
  String get faceData => _t('faceData');
  String get addFaceLoginData => _t('addFaceLoginData');
  String get localWifiMode => _t('localWifiMode');
  String get usingInternetConnection => _t('usingInternetConnection');
  String get reusableTags => _t('reusableTags');
  String get singleReusableEnabled => _t('singleReusableEnabled');
  String get onlyWebReusableEnabled => _t('onlyWebReusableEnabled');
  String get faceMatchedSuccessfully => _t('faceMatchedSuccessfully');
  String get faceNotRecognised => _t('faceNotRecognised');
  String get noSavedFaceDataFound => _t('noSavedFaceDataFound');
  String get saveFaceLabel => _t('saveFaceLabel');
  String get faceDetectedLabel => _t('faceDetectedLabel');
  String get noFaceDetectedLabel => _t('noFaceDetectedLabel');
  String get faceModelNotLoaded => _t('faceModelNotLoaded');
  String get cameraPermissionRequired => _t('cameraPermissionRequired');
  String get registerFace => _t('registerFace');
  String get deviceIpNotFound => _t('deviceIpNotFound');
  String get pleaseConnectToWifi => _t('pleaseConnectToWifi');
  String get localWifiModeEnabledMsg => _t('localWifiModeEnabledMsg');
  String get internetModeEnabled => _t('internetModeEnabled');
  String get trayMode => _t('trayMode');
  String get trayModeDisabled => _t('trayModeDisabled');
  String get trayModeEnabledMsg => _t('trayModeEnabledMsg');
  String get trayModeDisabledMsg => _t('trayModeDisabledMsg');
  String get selectTrayDevice => _t('selectTrayDevice');
  String get trayConnected => _t('trayConnected');
  String get trayNotConnected => _t('trayNotConnected');
  String get trayDeviceSelected => _t('trayDeviceSelected');
  String get bluetoothPermissionRequired => _t('bluetoothPermissionRequired');
  String get noBondedBluetoothDevices => _t('noBondedBluetoothDevices');
  String get r6Mode => _t('r6Mode');
  String get r6ModeDisabled => _t('r6ModeDisabled');
  String get r6ModeEnabledMsg => _t('r6ModeEnabledMsg');
  String get r6ModeDisabledMsg => _t('r6ModeDisabledMsg');
  String get selectR6Device => _t('selectR6Device');
  String get r6DeviceSelected => _t('r6DeviceSelected');
  String get loginErrorLabel => _t('loginErrorLabel');

  String get enterExhibition => _t('enterExhibition');
  String get enterRemark => _t('enterRemark');
  String get enterSize => _t('enterSize');
  String get enterLength => _t('enterLength');
  String get enterFinePercentage => _t('enterFinePercentage');
  String get enterWastage => _t('enterWastage');

  // Customer Dialog getters
  String get fieldCustomerName => _t('fieldCustomerName');
  String get fieldMobileNumber => _t('fieldMobileNumber');
  String get fieldEmailAddress => _t('fieldEmailAddress');
  String get fieldPanNumber => _t('fieldPanNumber');
  String get fieldGstNumber => _t('fieldGstNumber');
  String get fieldStreetAddress => _t('fieldStreetAddress');
  String get fieldCity => _t('fieldCity');

  // Validations getters
  String get validationNameRequired => _t('validationNameRequired');
  String get validationMobileRequired => _t('validationMobileRequired');
  String get validationMobileDigits => _t('validationMobileDigits');
  String get validationPanDigits => _t('validationPanDigits');
  String get validationGstDigits => _t('validationGstDigits');

  // Product Management getters
  String get noLocalDataToExportSyncFirst => _t('noLocalDataToExportSyncFirst');
  String get dataSyncSuccessfully => _t('dataSyncSuccessfully');

  String mobileLabel(String mobile) =>
      _t('mobileLabel').replaceAll('{mobile}', mobile);

  String mobileGstLabel(String mobile, String gst) => _t('mobileGstLabel')
      .replaceAll('{mobile}', mobile)
      .replaceAll('{gst}', gst);

  String get itemsSavedSuccessfully => _t('itemsSavedSuccessfully');
  String get couldNotReadFile => _t('couldNotReadFile');
  String get noHeadersInExcel => _t('noHeadersInExcel');
  String get importingExcelData => _t('importingExcelData');
  String get failedToSaveItemsToServer => _t('failedToSaveItemsToServer');
  String get failedToClearServerStock => _t('failedToClearServerStock');
  String get failedToSaveFaceToServer => _t('failedToSaveFaceToServer');
  String get deviceConfigNotFound => _t('deviceConfigNotFound');
  String get pleaseScanValidRfid => _t('pleaseScanValidRfid');
  String get customApiUrlHint => _t('customApiUrlHint');

  String importSuccessfulCount(int count) =>
      _t('importSuccessful').replaceAll('{count}', '$count');
  String importWithErrorsList(String errors) =>
      _t('importWithErrors').replaceAll('{errors}', errors);
  String fieldsImportedProgress(int imported, int total) => _t('fieldsImportedProgress')
      .replaceAll('{imported}', '$imported')
      .replaceAll('{total}', '$total');
  String failedFieldsLabel(String fields) =>
      _t('failedFieldsLabel').replaceAll('{fields}', fields);
  String failedToPrintPdfMessage(String error) =>
      _t('failedToPrintPdf').replaceAll('{error}', error);
  String errorSavingData(String message) =>
      _t('errorSavingData').replaceAll('{message}', message);
  String errorClearingData(String message) =>
      _t('errorClearingData').replaceAll('{message}', message);
  String recordsDeletedSuccess(int count) =>
      _t('recordsDeletedSuccess').replaceAll('{count}', '$count');
  String selectOption(String label) =>
      _t('selectOption').replaceAll('{label}', label);

  String sampleOutItemsCount(String no, int count) => _t('sampleOutItemsCount')
      .replaceAll('{no}', no)
      .replaceAll('{count}', '$count');

  String nItems(int count) =>
      _t('nItems').replaceAll('{count}', '$count');

  String itemsTitle(String type) =>
      _t('itemsTitle').replaceAll('{type}', type);

  String itemsCountLabel(int count) =>
      _t('itemsCountLabel').replaceAll('{count}', '$count');

  String exportingRows(int count) =>
      _t('exportingRows').replaceAll('{count}', '$count');

  String powerLabel(int val) =>
      _t('powerLabel').replaceAll('{val}', '$val');

  String selectFilterType(String type) =>
      _t('selectFilterType').replaceAll('{type}', type);

  String reportSentTo(String email) =>
      _t('reportSentTo').replaceAll('{email}', email);

  String selectLabel(String label) => _t('selectLabel').replaceAll('{label}', label);
  String confirmDeleteProduct(String name, String code) => _t('confirmDeleteProduct').replaceAll('{name}', name).replaceAll('{code}', code);

  String verificationUploadFailed(String message) =>
      _t('verificationUploadFailed').replaceAll('{message}', message);

  String searchErrorMessage(String error) =>
      _t('searchErrorMessage').replaceAll('{error}', error);

  String failedWithMessage(String message) =>
      _t('failedWithMessage').replaceAll('{message}', message);

  String comingSoonFor(String feature) =>
      _t('comingSoon').replaceAll('{feature}', feature);

  String exportFailed(String error) =>
      _t('exportFailed').replaceAll('{error}', error);

  String percentCompleted(int percent) =>
      _t('percentCompleted').replaceAll('{percent}', '$percent');

  String syncedItemsCount(int synced, int total) => _t('syncedItemsCount')
      .replaceAll('{synced}', '$synced')
      .replaceAll('{total}', '$total');

  String notSyncedCount(int count) =>
      _t('notSynced').replaceAll('{count}', '$count');

  String showMoreCount(int count) =>
      _t('showMore').replaceAll('{count}', '$count');

  String selectItem(String item) =>
      _t('selectItem').replaceAll('{item}', item);

  String languageLabel(String code) {
    switch (code) {
      case 'hi':
        return hindi;
      case 'ar':
        return arabic;
      default:
        return english;
    }
  }

  static const Map<String, Map<String, String>> _data = {
    'en': {
      'settings': 'Settings',
      'product': 'Product',
      'inventory': 'Inventory',
      'search': 'Search',
      'order': 'Order',
      'stockTransfer': 'Stock Transfer',
      'report': 'Report',
      'quotations': 'Quotations',
      'deliveryChallan': 'Delivery Challan',
      'labelTodayRate': 'Label Today Rate',
      'sampleIn': 'Sample In',
      'sampleOut': 'Sample Out',
      'home': 'Home',
      'logout': 'Logout',
      'account': 'Account',
      'usernamePassword': 'Username & Password',
      'userPermission': 'User Permission',
      'managePermission': 'Manage Permission',
      'email': 'Email',
      'backup': 'Backup',
      'dataBackup': 'Data Backup',
      'autoSync': 'Auto Sync',
      'enableAutomaticSync': 'Enable automatic sync',
      'notifications': 'Notifications',
      'notificationSettings': 'Notification settings',
      'branches': 'Branches',
      'branchManagement': 'Branch management',
      'customApi': 'Custom API',
      'configureApiUrl': 'Configure API base URL',
      'sheetUrl': 'Sheet URL',
      'setGoogleSheetUrl': 'Set Google Sheet URL',
      'stockTransferUrl': 'Stock Transfer URL',
      'stockTransferApiUrl': 'Stock Transfer API URL',
      'clearData': 'Clear Data',
      'clearLocalData': 'Clear local data',
      'language': 'Language',
      'location': 'Location',
      'selectLanguage': 'Select Language',
      'english': 'English',
      'hindi': 'Hindi',
      'arabic': 'Arabic',
      'locationList': 'Location List',
      'selectDate': 'Select Date',
      'headerSr': 'Sr',
      'date': 'Date',
      'userId': 'UserId',
      'address': 'Address',
      'noLocationsFound': 'No locations found',
      'failedToGetLocation': 'Failed to get location',
      'back': 'Back',
      'cancel': 'Cancel',
      'save': 'Save',
      'ok': 'OK',
      'route': 'Route',
      'defaultLoginEmail': 'Default login email',
      'permissionsFromServer': 'Permissions are assigned from the server at login.',
      'backupOptions': 'Backup Options',
      'backupChoose': 'Choose how you would like to back up your data.',
      'saveToDevice': 'Save to Device',
      'sendViaEmail': 'Send Via Email',
      'restoreBackup': 'Restore Backup',
      'autoSyncSettings': 'Auto Sync Settings',
      'syncInterval': 'Sync Interval:',
      'min15': '15 min',
      'min30': '30 min',
      'hour1': '1 hour',
      'hour24': '24 hours',
      'confirmClearData': 'Confirm Clear Data',
      'clearDataMessage': 'This will permanently delete all app data from this device. Continue?',
      'continueLabel': 'Continue',
      'verifyPassword': 'Verify Password',
      'password': 'Password',
      'incorrectPassword': 'Incorrect password',
      'enableNotifications': 'Enable notifications',
      'usernameLabel': 'Username',
      'send': 'Send',
      'restoreComplete': 'Restore complete. Restart app if needed.',
      'backupFailed': 'Backup failed',
      'savedTo': 'Saved',
      'selectedBranchIds': 'Selected branch IDs for sync',
      'enterEmailAddress': 'Enter Email Address',
      'clearBtn': 'Clear',
      'viewLocationList': 'View location list',
      'enabled': 'Enabled',
      'disabled': 'Disabled',
      'addSingleProduct': 'Add Single\nProduct',
      'addBulkProducts': 'Add Bulk\nProducts',
      'editProduct': 'Edit Product',
      'deleteProduct': 'Delete Product',
      'addBtn': 'Add',
      'delete': 'Delete',
      'reset': 'Reset',
      'apply': 'Apply',
      'importBtn': 'Import',
      'done': 'Done',
      'filters': 'Filters',
      'all': 'All',
      'actions': 'Actions',
      'listView': 'List View',
      'gridView': 'Grid View',
      'exporting': 'Exporting...',
      'exportPdf': 'Export PDF',
      'saveDetails': 'Save Details',
      'addNew': '➕ Add New',
      'failedToStartRfidScanner': 'Failed to start RFID scanner',
      'pleaseSelectVendorCategoryProductDesignPurity': 'Please select Vendor, Category, Product, Design and Purity',
      'epcRequired': 'EPC is required',
      'saved': 'Saved',
      'saveFailed': 'Save failed',
      'pleaseSelectCategoryProductDesign': 'Please select Category, Product and Design',
      'itemsSavedSuccessfully': 'Items saved successfully',
      'failedToSaveItemsToServer': 'Failed to save items to server',
      'failedToClearServerStock': 'Failed to clear stock data from server',
      'deviceConfigNotFound': 'Device configuration / Client Code not found',
      'pleaseScanValidRfid': 'Please scan RFID tag / No valid EPC/RFID data',
      'errorSavingData': 'Error saving data: {message}',
      'errorClearingData': 'Error clearing data: {message}',
      'recordsDeletedSuccess': '{count} records deleted successfully',
      'failedToPrintPdf': 'Failed to print PDF: {error}',
      'failedToSaveFaceToServer': 'Failed to save face info to server',
      'failedFieldsLabel': 'Failed: {fields}',
      'customApiUrlHint': 'https://your-api.com/',
      'selectOption': 'Select {label}',
      'addScannedTagsBeforeSaving': 'Add scanned tags with item codes before saving',
      'couldNotReadFile': 'Could not read file',
      'noHeadersInExcel': 'No headers found in Excel file',
      'productUpdatedSuccessfully': 'Product updated successfully!',
      'failedToUpdateProduct': 'Failed to update product.',
      'productDeletedSuccessfully': 'Product deleted successfully!',
      'noProductsToExport': 'No products to export.',
      'noProductsMatchingFilters': 'No products matching filters found.',
      'tryResettingFilters': 'Try resetting your filters or search query.',
      'apiActiveCannotEdit': 'This product is ApiActive and cannot be edited.',
      'nameRequired': 'Name is required',
      'scanTagsToAddRows': 'Scan tags to add rows',
      'errorWithMessage': 'Error: {message}',
      'errorPickingPhoto': 'Error picking photo: {error}',
      'errorGeneratingPdf': 'Error generating PDF: {error}',
      'importSuccessful': 'Import successful: {count} fields',
      'importWithErrors': 'Imported with errors: {errors}',
      'fieldsImportedProgress': '{imported} / {total} fields imported',
      'addType': 'Add {type}',
      'enterTypeName': 'Enter {type} name',
      'confirmDeleteProduct': 'Are you sure you want to delete product "{name}" with Item Code: {code}?',
      'tableView': 'Table View',
      'selectTableViewFields': 'Select the fields that should appear in the table view',
      'mainFields': 'Main Fields',
      'selectSheetFields': 'Select Sheet Fields',
      'mapColumn': 'Map Column',
      'itemDetails': 'Item Details',
      'importingExcelData': 'Importing Excel Data',
      'generalDetails': 'General Details',
      'weights': 'Weights',
      'makingStonePricing': 'Making & Stone Pricing',
      'rfidStoreDetails': 'RFID & Store Details',
      'productTitleName': 'Product Title / Name',
      'pieces': 'Pieces',
      'grossWeightG': 'Gross Weight (g)',
      'netWeightG': 'Net Weight (g)',
      'stoneWeightG': 'Stone Weight (g)',
      'diamondWeightG': 'Diamond Weight (g)',
      'makingPerGram': 'Making / Gram',
      'rfidTag': 'RFID Tag',
      'epcValueUhf': 'EPC Value (UHF)',
      'skuCode': 'SKU Code',
      'branchName': 'Branch Name',
      'boxName': 'Box Name',
      'counterName': 'Counter Name',
      'productName': 'Product Name',
      'fieldEpc': 'EPC',
      'fieldVendor': 'Vendor',
      'fieldSku': 'SKU',
      'fieldRfidCode': 'RFID Code',
      'fieldCategory': 'Category',
      'fieldProduct': 'Product',
      'fieldDesign': 'Design',
      'fieldPurity': 'Purity',
      'fieldGrossWeight': 'Gross Weight',
      'fieldStoneWeight': 'Stone Weight',
      'fieldDiamondWeight': 'Diamond Weight',
      'fieldNetWeight': 'Net Weight',
      'fieldMakingGram': 'Making/Gram',
      'fieldMakingPercent': 'Making %',
      'fieldFixMaking': 'Fix Making',
      'fieldFixWastage': 'Fix Wastage',
      'fieldStoneAmount': 'Stone Amount',
      'fieldDiamondAmount': 'Diamond Amount',
      'itemCode': 'Item Code',
      'rfidCode': 'RFID Code',
      'searchSkuCodeName': 'Search SKU, Code, Name...',
      'productListCount': 'Product List ({count})',
      'labelledStockReport': 'Labelled Stock Report',
      'totalItems': 'Total Items: {count}',
      'pageOf': 'Page {page} of {total}',
      'lblRfid': 'RFID',
      'lblCode': 'Code',
      'lblGrossWt': 'G. Wt',
      'lblNetWt': 'N. Wt',
      'lblStoneWt': 'S. Wt',
      'lblDiamondWt': 'D. Wt',
      'colGrossWt': 'Gross Wt',
      'colStoneWt': 'Stone Wt',
      'colDiamondWt': 'Diamond Wt',
      'colNetWt': 'Net Wt',
      'colStoneAmt': 'Stone Amt',
      'colDiamondAmt': 'Diamond Amt',
      'colRfid': 'RFID',
      'colSku': 'SKU',
      'colEpc': 'EPC',
      'colVendor': 'Vendor',
      'camera': 'Camera',
      'gallery': 'Gallery',
      'selectLabel': 'Select {label}',
      'addLabel': 'Add {label}',
      'pleaseSelectSampleOutNoFirst': 'Please select Sample Out No first',
      'customerProfile': 'Customer Profile',
      'customerAddedSuccessfully': 'Customer added successfully',
      'customerAddedOffline': 'Customer saved offline — will sync when internet is available',
      'errorAddingCustomer': 'Error adding customer',
      'confirmMatch': 'Confirm Match',
      'confirmAddToMatchedList': 'Are you sure you want to add this item in matched list?',
      'labelNo': 'No',
      'labelYes': 'Yes',
      'itemAddedToMatchedList': 'Item added in matched list',
      'removeMatch': 'Remove Match',
      'confirmRemoveFromMatchedList': 'Are you sure you want to remove this item from matched list?',
      'enterCustomerName': 'Enter customer name',
      'mobileLabel': 'Mobile: {mobile}',
      'mobileGstLabel': 'Mobile: {mobile} | GST: {gst}',
      'selectCustomerFirst': 'Select customer first',
      'enterSampleOutNo': 'Enter Sample Out No',
      'sampleOutItemsCount': '{no} ({count} items)',
      'sampleInSavedSuccessfully': 'Sample In saved successfully',
      'failedToSaveSampleIn': 'Failed to save Sample In',
      'sampleInList': 'Sample In List',
      'searchSoNoCustomerProduct': 'Search SO No, Customer or Product...',
      'noSampleInRecordsFound': 'No Sample In Records Found',
      'headerSoNo': 'S.O.No',
      'headerCustName': 'Cust Name',
      'headerRDate': 'R Date',
      'headerPName': 'P Name',
      'headerTWt': 'T Wt',
      'headerGwt': 'G.Wt',
      'headerSwt': 'S.Wt',
      'headerDwt': 'D.Wt',
      'headerQty': 'Qty',
      'description': 'Description',
      'deleteItem': 'Delete Item',
      'removeItemFromSampleOut': 'Remove this item from sample out?',
      'enterRfidItemcode': 'Enter RFID / Itemcode',
      'sampleOutFields': 'Sample Out Fields',
      'unknown': 'Unknown',
      'editSampleOut': 'Edit Sample Out',
      'createSampleOut': 'Create Sample Out',
      'rfidPower': 'RFID Power',
      'noItemsAdded': 'No Items Added',
      'headerSno': 'S.No',
      'total': 'Total',
      'action': 'Action',
      'nItems': '{count} Items',
      'sampleOutUpdatedSuccessfully': 'Sample Out updated successfully',
      'failedToUpdateSampleOut': 'Failed to update Sample Out',
      'sampleOutSavedSuccessfully': 'Sample Out saved successfully',
      'failedToSaveSampleOut': 'Failed to save Sample Out',
      'sampleOutList': 'Sample Out List',
      'searchSampleOutNoCustomer': 'Search Sample Out No or Customer Name...',
      'noSampleOutRecordsFound': 'No Sample Out Records Found',
      'createSampleOutHint': 'Create a new sample out using the + button.',
      'headerCustomer': 'Customer',
      'headerReturn': 'Return',
      'selectSampleOutNoToLoadItems': 'Select Sample Out No to load items',
      'status': 'Status',
      'headerPcs': 'Pcs',
      'headerFwWt': 'F+W Wt',
      'headerNwt': 'N.Wt',
      'returnLabel': 'Return',
      'nonReturn': 'Non Return',
      'returnDate': 'Return Date',
      'enterDescription': 'Enter description',
      'confirm': 'Confirm',
      'listBtn': 'List',
      'scanBtn': 'Scan',
      'stop': 'Stop',
      'gscan': 'Gscan',
      'update': 'Update',
      'transfer': 'Transfer',
      'stockVerificationReport': 'Stock Verification Report',
      'reportExportedSuccessfully': 'Report exported successfully',
      'exportingRows': 'Exporting... {count} rows',
      'errorLoadingSessions': 'Error loading sessions',
      'noSessionsFound': 'No sessions found',
      'errorLoadingReport': 'Error loading report',
      'noDataForSelectedDate': 'No data for selected date',
      'batchWise': 'BatchWise',
      'consolidated': 'Consolidated',
      'filter': 'Filter',
      'allBranches': 'All Branches',
      'fromDate': 'From Date',
      'toDate': 'To Date',
      'errorLoadingData': 'Error loading data',
      'noItemsFound': 'No items found',
      'headerItem': 'Item',
      'headerRfid': 'RFID',
      'batchDetails': 'Batch Details',
      'searchItemProductRfidCategory': 'Search item, product, RFID, category...',
      'matchedItems': 'Matched Items',
      'unmatchedItems': 'Unmatched Items',
      'itemsCountLabel': '{count} items',
      'noItems': 'No items',
      'notAvailable': 'N/A',
      'localServerRunning': 'Local Web Server Running',
      'localServerStopped': 'Local Web Server Stopped',
      'desktopUrl': 'Desktop URL:',
      'urlCopiedToClipboard': 'URL copied to clipboard',
      'noTagsScannedYet': 'No tags scanned yet.\nClick Scan to begin.',
      'totalScanned': 'Total Scanned: {count}',
      'scannedTagsCleared': 'Scanned tags cleared',
      'scanResetSuccessful': 'Scan reset successful',
      'assignRfidCode': 'Assign RFID Code',
      'assign': 'Assign',
      'scannedTagsSavedToDesktop': 'Scanned tags saved to desktop server',
      'scanHere': 'scan here',
      'loadingEllipsis': 'Loading...',
      'searchUnmatched': 'Search (Unmatched)',
      'searchAllItems': 'Search (All Items)',
      'searchType': 'Search Type',
      'labelStock': 'LabelStock',
      'enterRfidCustomOrderId': 'Enter RFID / CustomOrderId',
      'enterRfidBoxRfid': 'Enter RFID / Box RFID',
      'srNo': 'Sr No',
      'progress': 'Progress',
      'percent': 'Percent',
      'noUnmatchedItemsToSearch': 'No unmatched items to search',
      'typeRfidItemcodeToSearch': 'Type RFID / Itemcode to search specific items',
      'noItemsToSearch': 'No items to search',
      'noSearchableIdentifiers': 'No searchable identifiers found',
      'searchItemRfidProduct': 'Search item, RFID, product...',
      'qty': 'Qty',
      'mQty': 'M Qty',
      'mWt': 'M Wt',
      'grossWt': 'Gross Wt',
      'rfidNo': 'RFID No',
      'itemcode': 'Itemcode',
      'matchedItemsMenu': 'Matched Items',
      'unmatchedItemsMenu': 'Unmatched Items',
      'unlabelledItems': 'Unlabelled Items',
      'resumeScan': 'Resume Scan',
      'searchUnmatchedMenu': 'Search (Unmatched)',
      'noItemsFoundUnderScope': 'No items found under this scope',
      'allItemsMatchedScanStopped': 'All items matched. Scan stopped.',
      'pleaseWaitItemsLoading': 'Please wait, items are still loading',
      'noItemsInCurrentScope': 'No items in current scope',
      'noRfidEpcInScope': 'No RFID/EPC found on items in this scope',
      'allItemsAlreadyMatched': 'All items are already matched!',
      'previousScanRestored': 'Previous scan restored',
      'errorSessionExpired': 'Error: session expired',
      'stockVerificationUploaded': 'Stock verification uploaded successfully!',
      'verificationUploadFailed': 'Verification upload failed: {message}',
      'sendReport': 'Send Report',
      'savedEmails': 'Saved Emails:',
      'pleaseEnterOrSelectEmail': 'Please enter or select an email',
      'pleaseEnterValidEmail': 'Please enter a valid email address',
      'reportSentTo': 'Report sent successfully to {email}',
      'failedToSendEmail': 'Failed to send email',
      'failedWithMessage': 'Failed: {message}',
      'inventoryScanReportSubject': 'Inventory Scan Report',
      'reportEmailBody': '<h2>Here is your scan report</h2><p>Details attached.</p>',
      'searchProductRfidEpc': 'Search product, RFID, EPC...',
      'selectFilterType': 'Select {type}',
      'itemsTitle': '{type} Items',
      'searchErrorMessage': 'Search error: {error}',
      'error': 'Error',
      'customerOrdersList': 'Customer Orders List',
      'deleteOrder': 'Delete Order',
      'deleteOrderConfirm': 'Are you sure you want to delete custom order #{id}?',
      'searchOrderHint': 'Search by Order No or Customer...',
      'orderDeletedSuccessfully': '✅ Custom Order Deleted Successfully',
      'deliveryChallanList': 'Delivery Challan List',
      'searchChallanHint': 'Search Challan No or Customer Name...',
      'noChallansFound': 'No Delivery Challan Found',
      'confirmDeleteChallan': 'Are you sure you want to delete this delivery challan?',
      'challanDeletedSuccessfully': '✅ Delivery Challan Deleted Successfully',
      'noOrdersFound': 'No Custom Orders Found',
      'walkInCustomer': 'Walk-in Customer',
      'headerOrderNo': 'Order No',
      'headerFineWt': 'Fine+ Wt',
      'headerTaxAmt': 'Tax Amt',
      'headerTotalAmt': 'Total Amt',
      'createChallanHint': 'Create a new challan by clicking the + button.',
      'headerChallanNo': 'Challan No',
      'welcomeTo': 'Welcome To',
      'sparkleRfid': 'Sparkle RFID',
      'pleaseLoginToContinue': 'Please log in to continue',
      'rememberMe': 'Remember Me',
      'forgotPassword': 'Forgot Password?',
      'useFaceDetectionLogin': 'Use face detection to continue login',
      'logIn': 'Log In',
      'logInWithFace': 'Log In with Face',
      'troubleLogin': 'Trouble login? ',
      'contactUsClicked': 'Contact us clicked',
      'contactUs': 'Contact Us',
      'expiryWarning': 'Expiry Warning',
      'faceLogin': 'Face Login',
      'alignFaceInCircle': 'Align your face within the circle',
      'scanningFace': 'Scanning face...',
      'faceScanSimulationComplete': 'Face scan simulation completed. Face login not registered.',
      'fieldCustomerName': 'Customer Name *',
      'fieldMobileNumber': 'Mobile Number *',
      'fieldEmailAddress': 'Email Address',
      'fieldPanNumber': 'PAN Number',
      'fieldGstNumber': 'GST Number',
      'fieldStreetAddress': 'Street Address',
      'fieldCity': 'City',
      'validationNameRequired': 'Please enter customer name',
      'validationMobileRequired': 'Please enter mobile number',
      'validationMobileDigits': 'Enter a valid 10-digit mobile number',
      'validationPanDigits': 'PAN must be exactly 10 characters',
      'validationGstDigits': 'GST must be exactly 15 characters',
      'noLocalDataToExportSyncFirst': 'No local data to export. Sync data first.',
      'importExcel': 'Import\nExcel',
      'exportExcel': 'Export\nExcel',
      'syncData': 'Sync\nData',
      'scanToDesktop': 'Scan to\nDesktop',
      'syncSheetData': 'Sync Sheet\nData',
      'uploadDataToServer': 'Upload Data\nTo Server',
      'openProductList': 'Open Product List',
      'exportingExcel': 'Exporting Excel...',
      'dataSyncSuccessfully': 'Data Sync Successfully!',
      'showLess': 'Show less',
      'addAtLeastOneItem': 'Add at least one item to set order details',
      'orderScreen': 'Order Screen',
      'orderDetails': 'Order Details',
      'itemAmt': 'Item Amt',
      'confirmDeleteItem': 'Are you sure you want to delete this item?',
      'gstLabel': 'GST 3.00%',
      'totalAmount': 'Total Amount',
      'orderSavedSuccessfully': 'Order saved successfully',
      'orderSavedOffline': 'Order saved offline — will sync when internet is available',
      'orderPendingSync': 'Pending sync',
      'syncOrdersNow': 'Sync orders',
      'offlineOrderMode': 'Offline mode — using cached data',
      'failedToSaveOrder': 'Failed to save order',
      'confirmDeleteChallanItem': 'Are you sure you want to delete this item from the challan?',
      'challanFields': 'Challan Fields',
      'itemName': 'Item Name',
      'rate': 'Rate',
      'makingChg': 'Making Chg',
      'amount': 'Amount',
      'fineWt': 'Fine Wt',
      'editDeliveryChallan': 'Edit Delivery Challan',
      'createDeliveryChallan': 'Create Delivery Challan',
      'challanSavedSuccessfully': 'Delivery Challan saved successfully',
      'challanUpdatedSuccessfully': 'Delivery Challan updated successfully',
      'failedToSubmitChallan': 'Failed to submit Delivery Challan',
      'quotationList': 'Quotation List',
      'searchQuotationHint': 'Search by Quotation No or Customer...',
      'noQuotationsFound': 'No Quotations Found',
      'headerQNo': 'Q.No',
      'customerName': 'Customer Name',
      'addAtLeastOneQuotationItem': 'Add at least one item to set quotation details',
      'quotationDetails': 'Quotation Details',
      'quotationSavedSuccessfully': 'Quotation saved successfully',
      'quotationUpdatedSuccessfully': 'Quotation updated successfully',
      'failedToSaveQuotation': 'Failed to save quotation',
      'ratesUpdatedSuccessfully': 'Rates updated successfully',
      'failedToUpdateRates': 'Failed to update rates',
      'noRatesFound': 'No rates found',
      'todayRatePerGm': "Today's Rate / Gm",
      'searchError': 'Search error: {error}',
      'noSearchableIdentifiersFound': 'No searchable identifiers found',
      'searchSampleOutHint': 'Search Sample Out No or Customer Name...',
      'returnTitle': 'Return',
      'selectSampleOutNoFirst': 'Please select Sample Out No first',
      'confirmAddMatched': 'Are you sure you want to add this item in matched list?',
      'no': 'No',
      'yes': 'Yes',
      'itemAddedInMatchedList': 'Item added in matched list',
      'confirmRemoveMatched': 'Are you sure you want to remove this item from matched list?',
      'itemsLabel': 'Items',
      'exportingProgress': 'Exporting... {count} rows',
      'customOrderFields': 'Custom Order Fields',
      'totalWeight': 'Total Weight',
      'packingWt': 'Packing Wt',
      'ratePerGram': 'Rate Per Gram',
      'colors': 'Colors',
      'screwType': 'Screw Type',
      'polishType': 'Polish Type',
      'finePercent': 'Fine %',
      'wastagePercent': 'Wastage %',
      'deliveryDate': 'Delivery Date',
      'mrp': 'MRP',
      'colorType': 'Color Type',
      'selectBranch': 'Select Branch',
      'salesman': 'Salesman',
      'pleaseSelectBranchAndDate': 'Please select branch and date.',
      'orderDate': 'Order Date',
      'enterExhibition': 'Enter Exhibition',
      'enterRemark': 'Enter Remark',
      'enterSize': 'Enter Size',
      'enterLength': 'Enter Length',
      'enterFinePercentage': 'Enter Fine Percentage',
      'enterWastage': 'Enter Wastage',
      'size': 'Size',
      'length': 'Length',
      'hallmarkAmt': 'Hallmark Amt',
      'finePlusWt': 'Fine+ Weight',
      'remark': 'Remark',
      'tapToEnter': 'Tap to enter…',
      'categoryFirst': 'Category first',
      'productFirst': 'Product first',
      'designFirst': 'Design first',
      'selectVendorFirst': 'Select vendor first',
      'retry': 'Retry',
      'select': 'select',
      'import': 'Import',
      'box': 'Box',
      'item': 'Item',
      'tapTo': 'Tap to ',
      'chooseFile': 'choose file',
      'matched': 'Matched',
      'unmatched': 'Unmatched',
      'formatsLabel': 'Formats: xls, xlsx',
      'maxFileSize': 'Max: 250 MB',
      'totalInv': 'Total Inv',
      'start': 'Start',
      'end': 'End',
      'totalQty': 'Total Qty',
      'match': 'Match',
      'unmatch': 'Unmatch',
      'privacyPolicy': 'Privacy Policy',
      'viewPrivacyPolicy': 'View our privacy policy',
      'faceData': 'Face Data',
      'addFaceLoginData': 'Add face login data',
      'localWifiMode': 'Local WiFi Mode',
      'usingInternetConnection': 'Using internet connection',
      'reusableTags': 'Reusable Tags',
      'singleReusableEnabled': 'Single + Reusable enabled',
      'onlyWebReusableEnabled': 'Only WebReusable enabled',
      'faceMatchedSuccessfully': 'Face matched successfully',
      'faceNotRecognised': 'Face not recognised',
      'noSavedFaceDataFound': 'No saved face data found',
      'saveFaceLabel': 'Save Face',
      'faceDetectedLabel': 'Face detected',
      'noFaceDetectedLabel': 'No face detected',
      'faceModelNotLoaded': 'Face model not loaded',
      'cameraPermissionRequired': 'Camera permission required',
      'registerFace': 'Register Face',
      'deviceIpNotFound': 'Device IP not found',
      'pleaseConnectToWifi': 'Please connect to WiFi for Local Mode',
      'localWifiModeEnabledMsg': 'Local WiFi Mode Enabled',
      'internetModeEnabled': 'Internet Mode Enabled',
      'trayMode': 'Tray Mode',
      'trayModeDisabled': 'Handheld gun mode',
      'trayModeEnabledMsg': 'Tray mode enabled',
      'trayModeDisabledMsg': 'Tray mode disabled',
      'selectTrayDevice': 'Select Bluetooth tray',
      'trayConnected': 'Connected',
      'trayNotConnected': 'Not connected',
      'trayDeviceSelected': 'Tray device selected',
      'bluetoothPermissionRequired': 'Bluetooth permission is required for RFID Bluetooth readers',
      'noBondedBluetoothDevices': 'No Bluetooth RFID devices found. Turn on the reader and try again.',
      'r6Mode': 'R6 Bluetooth Mode',
      'r6ModeDisabled': 'Off',
      'r6ModeEnabledMsg': 'R6 mode enabled',
      'r6ModeDisabledMsg': 'R6 mode disabled',
      'selectR6Device': 'Select Chainway R6',
      'r6DeviceSelected': 'R6 device selected',
      'loginErrorLabel': 'Login Error',
      'transferType': 'Transfer Type',
      'from': 'From',
      'to': 'To',
      'stockRequests': 'Stock Requests',
      'inRequest': 'In Request',
      'outRequest': 'Out Request',
      'itemCodeOrRfid': 'Item Code / RFID',
      'itemCodeLabel': 'Item Code',
      'selectedQty': 'Selected Qty',
      'selectItemsToTransfer': 'Select items to transfer',
      'transferPreview': 'Transfer Preview',
      'submitTransfer': 'Submit Transfer',
      'transferredBy': 'Transferred By',
      'transferredTo': 'Transferred To',
      'remarks': 'Remarks',
      'pending': 'Pending',
      'approved': 'Approved',
      'rejected': 'Rejected',
      'lost': 'Lost',
      'transferBy': 'Transfer By',
      'transferToCol': 'Transfer To',
      'deleteTransferConfirm': 'Delete this transfer request?',
      'stockTransfers': 'Stock Transfers',
      'approve': 'Approve',
      'reject': 'Reject',
      'category': 'Category',
      'design': 'Design',
      'transferDetails': 'Transfer Details',
      'transferSuccess': 'Transfer successful',
      'transferFailed': 'Transfer failed',
      'statusFilter': 'Status Filter',
      'selectAtLeastOneItem': 'Please select at least one item',
      'selectEmployee': 'Select Employee',
      'selectEmployeeError': 'Please select an employee',
      'admin': 'Admin',
      'clearServerStockConfirm': 'Are you sure you want to clear/delete the stock data from server?',
    },
    'hi': {
      'settings': 'सेटिंग्स',
      'product': 'उत्पाद',
      'inventory': 'इन्वेंटरी',
      'search': 'खोज',
      'order': 'ऑर्डर',
      'stockTransfer': 'स्टॉक ट्रांसफर',
      'report': 'रिपोर्ट',
      'quotations': 'कोटेशन',
      'deliveryChallan': 'डिलीवरी चालान',
      'labelTodayRate': 'आज का रेट',
      'sampleIn': 'सैंपल इन',
      'sampleOut': 'सैंपल आउट',
      'home': 'होम',
      'logout': 'लॉगआउट',
      'account': 'खाता',
      'usernamePassword': 'उपयोगकर्ता नाम और पासवर्ड',
      'userPermission': 'उपयोगकर्ता अनुमति',
      'managePermission': 'अनुमति प्रबंधित करें',
      'email': 'ईमेल',
      'backup': 'बैकअप',
      'dataBackup': 'डेटा बैकअप',
      'autoSync': 'स्वचालित सिंक',
      'enableAutomaticSync': 'स्वचालित सिंक सक्षम करें',
      'notifications': 'सूचनाएं',
      'notificationSettings': 'सूचना सेटिंग्स',
      'branches': 'शाखाएं',
      'branchManagement': 'शाखा प्रबंधन',
      'customApi': 'कस्टम API',
      'configureApiUrl': 'API URL कॉन्फ़िगर करें',
      'sheetUrl': 'शीट URL',
      'setGoogleSheetUrl': 'Google Sheet URL सेट करें',
      'stockTransferUrl': 'स्टॉक ट्रांसफर URL',
      'stockTransferApiUrl': 'स्टॉक ट्रांसफर API URL',
      'clearData': 'डेटा साफ़ करें',
      'clearLocalData': 'स्थानीय डेटा साफ़ करें',
      'language': 'भाषा',
      'location': 'स्थान',
      'selectLanguage': 'भाषा चुनें',
      'english': 'English',
      'hindi': 'हिन्दी',
      'arabic': 'Arabic',
      'locationList': 'स्थान सूची',
      'selectDate': 'तारीख चुनें',
      'headerSr': 'क्रम',
      'date': 'तारीख',
      'userId': 'UserId',
      'address': 'पता',
      'noLocationsFound': 'कोई स्थान नहीं मिला',
      'failedToGetLocation': 'स्थान प्राप्त करने में विफल',
      'back': 'वापस',
      'cancel': 'रद्द करें',
      'save': 'सेव',
      'ok': 'ठीक',
      'route': 'मार्ग',
      'defaultLoginEmail': 'डिफ़ॉल्ट लॉगिन ईमेल',
      'permissionsFromServer': 'लॉगिन पर सर्वर से अनुमतियां असाइन की जाती हैं।',
      'backupOptions': 'बैकअप विकल्प',
      'backupChoose': 'अपना डेटा बैकअप कैसे करना चाहते हैं, चुनें।',
      'saveToDevice': 'डिवाइस में सेव करें',
      'sendViaEmail': 'ईमेल द्वारा भेजें',
      'restoreBackup': 'बैकअप पुनर्स्थापित करें',
      'autoSyncSettings': 'स्वचालित सिंक सेटिंग्स',
      'syncInterval': 'सिंक अंतराल:',
      'min15': '15 मिनट',
      'min30': '30 मिनट',
      'hour1': '1 घंटा',
      'hour24': '24 घंटे',
      'confirmClearData': 'डेटा साफ़ करने की पुष्टि करें',
      'clearDataMessage': 'यह इस डिवाइस से सभी ऐप डेटा स्थायी रूप से हटा देगा। जारी रखें?',
      'continueLabel': 'जारी रखें',
      'verifyPassword': 'पासवर्ड सत्यापित करें',
      'password': 'पासवर्ड',
      'incorrectPassword': 'गलत पासवर्ड',
      'enableNotifications': 'सूचनाएं सक्षम करें',
      'usernameLabel': 'उपयोगकर्ता नाम',
      'send': 'भेजें',
      'restoreComplete': 'पुनर्स्थापना पूर्ण। आवश्यकता हो तो ऐप पुनः प्रारंभ करें।',
      'backupFailed': 'बैकअप विफल',
      'savedTo': 'सेव किया',
      'selectedBranchIds': 'सिंक के लिए चयनित शाखा ID',
      'enterEmailAddress': 'ईमेल पता दर्ज करें',
      'clearBtn': 'साफ़ करें',
      'viewLocationList': 'स्थान सूची देखें',
      'enabled': 'सक्षम',
      'disabled': 'अक्षम',
      'addSingleProduct': 'एकल उत्पाद जोड़ें',
      'addBulkProducts': 'बल्क उत्पाद जोड़ें',
      'editProduct': 'उत्पाद संपादित करें',
      'deleteProduct': 'उत्पाद हटाएं',
      'addBtn': 'जोड़ें',
      'delete': 'हटाएं',
      'reset': 'रीसेट',
      'apply': 'लागू करें',
      'importBtn': 'आयात',
      'done': 'पूर्ण',
      'filters': 'फ़िल्टर',
      'all': 'सभी',
      'actions': 'कार्रवाई',
      'listView': 'सूची दृश्य',
      'gridView': 'ग्रिड दृश्य',
      'exporting': 'निर्यात हो रहा है...',
      'exportPdf': 'PDF निर्यात',
      'saveDetails': 'विवरण सहेजें',
      'addNew': '➕ नया जोड़ें',
      'failedToStartRfidScanner': 'RFID स्कैनर शुरू करने में विफल',
      'pleaseSelectVendorCategoryProductDesignPurity': 'कृपया विक्रेता, श्रेणी, उत्पाद, डिज़ाइन और शुद्धता चुनें',
      'epcRequired': 'EPC आवश्यक है',
      'saved': 'सहेजा गया',
      'saveFailed': 'सहेजना विफल',
      'pleaseSelectCategoryProductDesign': 'कृपया श्रेणी, उत्पाद और डिज़ाइन चुनें',
      'itemsSavedSuccessfully': 'आइटम सफलतापूर्वक सहेजे गए',
      'failedToSaveItemsToServer': 'सर्वर पर आइटम सहेजने में विफल',
      'failedToClearServerStock': 'सर्वर से स्टॉक डेटा साफ़ करने में विफल',
      'deviceConfigNotFound': 'डिवाइस कॉन्फ़िगरेशन / क्लाइंट कोड नहीं मिला',
      'pleaseScanValidRfid': 'कृपया RFID टैग स्कैन करें / कोई वैध EPC/RFID डेटा नहीं',
      'errorSavingData': 'डेटा सहेजने में त्रुटि: {message}',
      'errorClearingData': 'डेटा साफ़ करने में त्रुटि: {message}',
      'recordsDeletedSuccess': '{count} रिकॉर्ड सफलतापूर्वक हटाए गए',
      'failedToPrintPdf': 'PDF प्रिंट करने में विफल: {error}',
      'failedToSaveFaceToServer': 'सर्वर पर फेस जानकारी सहेजने में विफल',
      'failedFieldsLabel': 'विफल: {fields}',
      'customApiUrlHint': 'https://your-api.com/',
      'selectOption': '{label} चुनें',
      'addScannedTagsBeforeSaving': 'सहेजने से पहले आइटम कोड के साथ स्कैन किए गए टैग जोड़ें',
      'couldNotReadFile': 'फ़ाइल पढ़ नहीं सकी',
      'noHeadersInExcel': 'Excel फ़ाइल में कोई हेडर नहीं मिला',
      'productUpdatedSuccessfully': 'उत्पाद सफलतापूर्वक अपडेट किया गया!',
      'failedToUpdateProduct': 'उत्पाद अपडेट करने में विफल।',
      'productDeletedSuccessfully': 'उत्पाद सफलतापूर्वक हटाया गया!',
      'reportEmailBody': '<h2>यहाँ आपकी स्कैन रिपोर्ट है</h2><p>विवरण संलग्न है।</p>',
      'noProductsToExport': 'निर्यात करने के लिए कोई उत्पाद नहीं।',
      'noProductsMatchingFilters': 'फ़िल्टर से मेल खाते कोई उत्पाद नहीं मिले।',
      'tryResettingFilters': 'अपने फ़िल्टर या खोज क्वेरी को रीसेट करने का प्रयास करें।',
      'apiActiveCannotEdit': 'यह उत्पाद ApiActive है और संपादित नहीं किया जा सकता।',
      'nameRequired': 'नाम आवश्यक है',
      'scanTagsToAddRows': 'पंक्तियाँ जोड़ने के लिए टैग स्कैन करें',
      'errorWithMessage': 'त्रुटि: {message}',
      'errorPickingPhoto': 'फ़ोटो चुनने में त्रुटि: {error}',
      'errorGeneratingPdf': 'PDF बनाने में त्रुटि: {error}',
      'importSuccessful': 'आयात सफल: {count} फ़ील्ड',
      'importWithErrors': 'त्रुटियों के साथ आयात: {errors}',
      'fieldsImportedProgress': '{imported} / {total} फ़ील्ड आयात',
      'addType': '{type} जोड़ें',
      'enterTypeName': '{type} नाम दर्ज करें',
      'confirmDeleteProduct': 'क्या आप वाकई उत्पाद "{name}" को आइटम कोड: {code} के साथ हटाना चाहते हैं?',
      'tableView': 'तालिका दृश्य',
      'selectTableViewFields': 'उन फ़ील्ड्स का चयन करें जो तालिका दृश्य में दिखाई देनी चाहिए',
      'mainFields': 'मुख्य फ़ील्ड',
      'selectSheetFields': 'शीट फ़ील्ड का चयन करें',
      'mapColumn': 'कॉलम मैप करें',
      'itemDetails': 'आइटम विवरण',
      'importingExcelData': 'Excel डेटा आयात हो रहा है',
      'generalDetails': 'सामान्य विवरण',
      'weights': 'वज़न',
      'makingStonePricing': 'मेकिंग और स्टोन मूल्य',
      'rfidStoreDetails': 'RFID और स्टोर विवरण',
      'productTitleName': 'उत्पाद शीर्षक / नाम',
      'pieces': 'टुकड़े',
      'grossWeightG': 'सकल वज़न (g)',
      'netWeightG': 'शुद्ध वज़न (g)',
      'stoneWeightG': 'स्टोन वज़न (g)',
      'diamondWeightG': 'डायमंड वज़न (g)',
      'makingPerGram': 'मेकिंग / ग्राम',
      'rfidTag': 'RFID टैग',
      'epcValueUhf': 'EPC मान (UHF)',
      'skuCode': 'SKU कोड',
      'branchName': 'शाखा नाम',
      'boxName': 'बॉक्स नाम',
      'counterName': 'काउंटर नाम',
      'productName': 'उत्पाद नाम',
      'fieldEpc': 'EPC',
      'fieldVendor': 'विक्रेता',
      'fieldSku': 'SKU',
      'fieldRfidCode': 'RFID कोड',
      'fieldCategory': 'श्रेणी',
      'fieldProduct': 'उत्पाद',
      'fieldDesign': 'डिज़ाइन',
      'fieldPurity': 'शुद्धता',
      'fieldGrossWeight': 'सकल वज़न',
      'fieldStoneWeight': 'स्टोन वज़न',
      'fieldDiamondWeight': 'डायमंड वज़न',
      'fieldNetWeight': 'शुद्ध वज़न',
      'fieldMakingGram': 'मेकिंग/ग्राम',
      'fieldMakingPercent': 'मेकिंग %',
      'fieldFixMaking': 'फिक्स मेकिंग',
      'fieldFixWastage': 'फिक्स वेस्टेज',
      'fieldStoneAmount': 'स्टोन राशि',
      'fieldDiamondAmount': 'डायमंड राशि',
      'itemCode': 'आइटम कोड',
      'rfidCode': 'RFID कोड',
      'searchSkuCodeName': 'SKU, कोड, नाम खोजें...',
      'productListCount': 'उत्पाद सूची ({count})',
      'labelledStockReport': 'लेबल्ड स्टॉक रिपोर्ट',
      'totalItems': 'कुल आइटम: {count}',
      'pageOf': 'पृष्ठ {page} / {total}',
      'lblRfid': 'RFID',
      'lblCode': 'कोड',
      'lblGrossWt': 'स. व.',
      'lblNetWt': 'शु. व.',
      'lblStoneWt': 'स्टोन व.',
      'lblDiamondWt': 'डाय. व.',
      'colGrossWt': 'सकल व.',
      'colStoneWt': 'स्टोन व.',
      'colDiamondWt': 'डाय. व.',
      'colNetWt': 'शुद्ध व.',
      'colStoneAmt': 'स्टोन रा.',
      'colDiamondAmt': 'डाय. रा.',
      'colRfid': 'RFID',
      'colSku': 'SKU',
      'colEpc': 'EPC',
      'colVendor': 'विक्रेता',
      'camera': 'कैमरा',
      'gallery': 'गैलरी',
      'selectLabel': '{label} चुनें',
      'addLabel': '{label} जोड़ें',
      'customerOrdersList': 'ग्राहक ऑर्डर सूची',
      'deleteOrder': 'ऑर्डर हटाएं',
      'deleteOrderConfirm': 'क्या आप वाकई कस्टम ऑर्डर #{id} हटाना चाहते हैं?',
      'searchOrderHint': 'ऑर्डर नंबर या ग्राहक द्वारा खोजें...',
      'orderDeletedSuccessfully': '✅ कस्टम ऑर्डर सफलतापूर्वक हटा दिया गया',
      'deliveryChallanList': 'डिलीवरी चालان सूची',
      'searchChallanHint': 'चालान नंबर या ग्राहक का नाम खोजें...',
      'noChallansFound': 'कोई डिलीवरी चालان नहीं मिला',
      'confirmDeleteChallan': 'क्या आप वाकई इस डिलीवरी चालान को हटाना चाहते हैं?',
      'challanDeletedSuccessfully': '✅ डिलीवरी चालान सफलतापूर्वक हटा दिया गया',
      'noOrdersFound': 'कोई कस्टम ऑर्डर नहीं मिला',
      'walkInCustomer': 'वॉक-इन ग्राहक',
      'headerOrderNo': 'ऑर्डर नंबर',
      'headerFineWt': 'फाइन+ वज़न',
      'headerTaxAmt': 'कर राशि',
      'headerTotalAmt': 'कुल राशि',
      'createChallanHint': '+ बटन पर क्लिक करके नया चालान बनाएं।',
      'headerChallanNo': 'चालान नंबर',
      'welcomeTo': 'आपका स्वागत है',
      'sparkleRfid': 'स्पार्कल RFID',
      'pleaseLoginToContinue': 'जारी रखने के लिए कृपया लॉग इन करें',
      'rememberMe': 'मुझे याद रखें',
      'forgotPassword': 'पासवर्ड भूल गए?',
      'useFaceDetectionLogin': 'लॉगिन जारी रखने के लिए फेस डिटेक्शन का उपयोग करें',
      'logIn': 'लॉग इन करें',
      'logInWithFace': 'फेस के साथ लॉग इन करें',
      'troubleLogin': 'लॉगिन में परेशानी? ',
      'contactUsClicked': 'हमसे संपर्क करें पर क्लिक किया गया',
      'contactUs': 'हमसे संपर्क करें',
      'expiryWarning': 'समाप्ति की चेतावनी',
      'faceLogin': 'फेस लॉगिन',
      'loginErrorLabel': 'लॉगिन त्रुटि',
      'showLess': 'कम दिखाएं',
      'addAtLeastOneItem': 'ऑर्डर विवरण सेट करने के लिए कम से कम एक आइटम जोड़ें',
      'orderScreen': 'ऑर्डर स्क्रीन',
      'orderDetails': 'ऑर्डर का विवरण',
      'itemAmt': 'आइटम राशि',
      'confirmDeleteItem': 'क्या आप वाकई इस आइटम को हटाना चाहते हैं?',
      'gstLabel': 'GST 3.00%',
      'totalAmount': 'कुल राशि',
      'orderSavedSuccessfully': 'ऑर्डर सफलतापूर्वक सहेजा गया',
      'orderSavedOffline': 'ऑर्डर ऑफ़लाइन सहेजा — इंटरनेट आने पर सिंक होगा',
      'customerAddedOffline': 'ग्राहक ऑफ़लाइन सहेजा — इंटरनेट आने पर सिंक होगा',
      'orderPendingSync': 'सिंक लंबित',
      'syncOrdersNow': 'ऑर्डर सिंक करें',
      'offlineOrderMode': 'ऑफ़लाइन मोड — कैश डेटा उपयोग में',
      'failedToSaveOrder': 'ऑर्डर सहेजने में विफल',
      'confirmDeleteChallanItem': 'क्या आप वाकई इस आइटम को चालान से हटाना चाहते हैं?',
      'challanFields': 'चालान फ़ील्ड',
      'itemName': 'आइटम का नाम',
      'rate': 'दर',
      'makingChg': 'मेकिंग चार्ज',
      'amount': 'राशि',
      'fineWt': 'फाइन वजन',
      'editDeliveryChallan': 'डिलीवरी चालान संपादित करें',
      'createDeliveryChallan': 'डिलीवरी चालान बनाएं',
      'challanSavedSuccessfully': 'डिलीवरी चालान सफलतापूर्वक सहेजा गया',
      'challanUpdatedSuccessfully': 'डिलीवरी चालान सफलतापूर्वक अपडेट किया गया',
      'failedToSubmitChallan': 'डिलीवरी चालान जमा करने में विफल',
      'quotationList': 'कोटेशन सूची',
      'searchQuotationHint': 'कोटेशन नंबर या ग्राहक द्वारा खोजें...',
      'noQuotationsFound': 'कोई कोटेशन नहीं मिला',
      'headerQNo': 'कोटेशन नंबर',
      'customerName': 'ग्राहक का नाम',
      'addAtLeastOneQuotationItem': 'कोटेशन विवरण सेट करने के लिए कम से कम एक आइटम जोड़ें',
      'quotationDetails': 'कोटेशन का विवरण',
      'quotationSavedSuccessfully': 'कोटेशन सफलतापूर्वक सहेजा गया',
      'quotationUpdatedSuccessfully': 'कोटेशन सफलतापूर्वक अपडेट किया गया',
      'failedToSaveQuotation': 'कोटेशन सहेजने में विफल',
      'ratesUpdatedSuccessfully': 'दरें सफलतापूर्वक अपडेट की गईं',
      'failedToUpdateRates': 'दरें अपडेट करने में विफल',
      'noRatesFound': 'कोई दर नहीं मिली',
      'todayRatePerGm': 'आज का रेट / ग्राम',
      'searchError': 'खोज त्रुटि: {error}',
      'noSearchableIdentifiersFound': 'कोई खोजने योग्य पहचानकर्ता नहीं मिला',
      'searchSampleOutHint': 'सैंपल आउट नंबर या ग्राहक का नाम खोजें...',
      'createSampleOutHint': 'प्लस बटन का उपयोग करके एक नया सैंपल आउट बनाएं।',
      'returnTitle': 'वापसी',
      'selectSampleOutNoFirst': 'कृपया पहले सैंपल आउट नंबर चुनें',
      'confirmAddMatched': 'क्या आप वाकई इस आइटम को मिलान सूची में जोड़ना चाहते हैं?',
      'no': 'नहीं',
      'yes': 'हाँ',
      'itemAddedInMatchedList': 'आइटم मिलान सूची में जोड़ा गया',
      'confirmRemoveMatched': 'क्या आप वाकई इस आइटम को मिलान सूची से हटाना चाहते हैं?',
      'itemsLabel': 'आइटम',
      'exportingProgress': 'निर्यात हो रहा है... {count} पंक्तियाँ',
      'customOrderFields': 'कस्टम ऑर्डर फ़ील्ड्स',
      'totalWeight': 'कुल वजन',
      'packingWt': 'पैकिंग वजन',
      'ratePerGram': 'दर प्रति ग्राम',
      'colors': 'रंग',
      'screwType': 'पेंच प्रकार',
      'polishType': 'पॉलिश प्रकार',
      'finePercent': 'फाइन %',
      'wastagePercent': 'वेस्टेज %',
      'deliveryDate': 'डिलीवरी की तारीख',
      'mrp': 'एमआरपी',
      'colorType': 'रंग का प्रकार',
      'selectBranch': 'शाखा चुनें',
      'salesman': 'सेल्समैन',
      'pleaseSelectBranchAndDate': 'कृपया शाखा और तिथि का चयन करें।',
      'orderDate': 'ऑर्डर की तारीख',
      'enterExhibition': 'प्रदर्शनी दर्ज करें',
      'enterRemark': 'टिप्पणी दर्ज करें',
      'enterSize': 'आकार दर्ज करें',
      'enterLength': 'लंबाई दर्ज करें',
      'enterFinePercentage': 'फाइन प्रतिशत दर्ज करें',
      'enterWastage': 'वेस्टेज दर्ज करें',
      'pleaseWaitItemsLoading': 'कृपया प्रतीक्षा करें, आइटम अभी भी लोड हो रहे हैं',
      'noItemsInCurrentScope': 'वर्तमान दायरे में कोई आइटम नहीं',
      'noRfidEpcInScope': 'इस दायरे के आइटम पर कोई RFID/EPC नहीं मिला',
      'allItemsAlreadyMatched': 'सभी आइटम पहले से ही मेल खाते हैं!',
      'previousScanRestored': 'पिछला स्कैन पुनर्स्थापित किया गया',
      'allItemsMatchedScanStopped': 'सभी आइटम मेल खा गए। स्कैन बंद कर दिया गया।',
      'scanResetSuccessful': 'स्कैन रीसेट सफल',
      'size': 'आकार',
      'length': 'लंबाई',
      'hallmarkAmt': 'हॉलमार्क राशि',
      'finePlusWt': 'फाइन+ वजन',
      'remark': 'टिप्पणी',
      'tapToEnter': 'दर्ज करने के लिए टैप करें…',
      'categoryFirst': 'पहले श्रेणी',
      'productFirst': 'पहले उत्पाद',
      'designFirst': 'पहले डिज़ाइन',
      'selectVendorFirst': 'पहले विक्रेता चुनें',
      'retry': 'पुनः प्रयास करें',
      'select': 'चुनें',
      'import': 'आयात',
      'labelStock': 'लेबल स्टॉक',
      'box': 'बॉक्स',
      'batchDetails': 'बैच विवरण',
      'matchedItems': 'मिलान की गई वस्तुएं',
      'unmatchedItems': 'असंगत वस्तुएं',
      'searchItemRfidProduct': 'आइटम, आरएफआईडी, उत्पाद खोजें...',
      'item': 'आइटम',
      'tapTo': 'टैप करें ',
      'chooseFile': 'फ़ाइल चुनें',
      'matched': 'मिलान किया गया',
      'unmatched': 'असंगत',
      'formatsLabel': 'प्रारूप: xls, xlsx',
      'maxFileSize': 'अधिकतम: 250 MB',
      'rfidPower': 'आरएफआईडी पावर',
      'totalInv': 'कुल इन्वेंटरी',
      'start': 'शुरू',
      'end': 'समाप्त',
      'totalQty': 'कुल मात्रा',
      'match': 'मिलान',
      'unmatch': 'असंगत',
      'privacyPolicy': 'गोपनीयता नीति',
      'viewPrivacyPolicy': 'हमारी गोपनीयता नीति देखें',
      'faceData': 'फेस डेटा',
      'addFaceLoginData': 'फेस लॉगिन डेटा जोड़ें',
      'localWifiMode': 'स्थानीय वाईफाई मोड',
      'usingInternetConnection': 'इंटरनेट कनेक्शन का उपयोग कर रहे हैं',
      'reusableTags': 'पुनर्प्रोज्य टैग',
      'singleReusableEnabled': 'सिंगल + पुनरुपयोगी सक्षम',
      'onlyWebReusableEnabled': 'केवल वेब-पुनरुपयोगी सक्षम',
      'faceMatchedSuccessfully': 'चेहरा सफलतापूर्वक मिल गया',
      'faceNotRecognised': 'चेहरा पहचाना नहीं गया',
      'noSavedFaceDataFound': 'कोई सहेजा गया फेस डेटा नहीं मिला',
      'saveFaceLabel': 'चेहरा सहेजें',
      'faceDetectedLabel': 'चेहरा पाया गया',
      'noFaceDetectedLabel': 'कोई चेहरा नहीं पाया गया',
      'faceModelNotLoaded': 'फेस मॉडल लोड नहीं हुआ',
      'cameraPermissionRequired': 'कैमरा अनुमति आवश्यक है',
      'registerFace': 'फेस पंजीकृत करें',
      'deviceIpNotFound': 'डिवाइस आईपी नहीं मिला',
      'pleaseConnectToWifi': 'स्थानीय मोड के लिए कृपया वाईफाई से कनेक्ट करें',
      'localWifiModeEnabledMsg': 'स्थानीय वाईफाई मोड सक्षम',
      'internetModeEnabled': 'इंटरनेट मोड सक्षम',
      'trayMode': 'ट्रे मोड',
      'trayModeDisabled': 'हैंडहेल्ड गन मोड',
      'trayModeEnabledMsg': 'ट्रे मोड सक्षम',
      'trayModeDisabledMsg': 'ट्रे मोड अक्षम',
      'selectTrayDevice': 'ब्लूटूथ ट्रे चुनें',
      'trayConnected': 'कनेक्टेड',
      'trayNotConnected': 'कनेक्ट नहीं',
      'trayDeviceSelected': 'ट्रे डिवाइस चुनी गई',
      'bluetoothPermissionRequired': 'RFID ब्लूटूथ रीडर के लिए ब्लूटूथ अनुमति आवश्यक है',
      'noBondedBluetoothDevices': 'कोई ब्लूटूथ RFID डिवाइस नहीं मिला। रीडर चालू करें और फिर कोशिश करें।',
      'r6Mode': 'R6 ब्लूटूथ मोड',
      'r6ModeDisabled': 'बंद',
      'r6ModeEnabledMsg': 'R6 मोड सक्षम',
      'r6ModeDisabledMsg': 'R6 मोड अक्षम',
      'selectR6Device': 'Chainway R6 चुनें',
      'r6DeviceSelected': 'R6 डिवाइस चुना गया',
      'searchItemProductRfidCategory': 'आइटम, उत्पाद, आरएफआईडी, श्रेणी खोजें...',
      'unknown': 'अज्ञात',
      'mobileLabel': 'मोबाइल: {mobile}',
      'mobileGstLabel': 'मोबाइल: {mobile} | GST: {gst}',
      'selectSampleOutNoToLoadItems': 'आइटम लोड करने के लिए सैंपल आउट नंबर चुनें',
      'transferType': 'ट्रांसफर प्रकार',
      'from': 'से',
      'to': 'को',
      'stockRequests': 'स्टॉक अनुरोध',
      'inRequest': 'इन रिक्वेस्ट',
      'outRequest': 'आउट रिक्वेस्ट',
      'itemCodeOrRfid': 'आइटम कोड / RFID',
      'itemCodeLabel': 'आइटम कोड',
      'selectedQty': 'चयनित मात्रा',
      'selectItemsToTransfer': 'ट्रांसफर के लिए आइटम चुनें',
      'transferPreview': 'ट्रांसफर पूर्वावलोकन',
      'submitTransfer': 'ट्रांसफर सबमिट करें',
      'transferredBy': 'द्वारा ट्रांसफर',
      'transferredTo': 'को ट्रांसफर',
      'remarks': 'टिप्पणी',
      'pending': 'लंबित',
      'approved': 'स्वीकृत',
      'rejected': 'अस्वीकृत',
      'lost': 'खोया',
      'transferBy': 'ट्रांसफर द्वारा',
      'transferToCol': 'ट्रांसफर को',
      'deleteTransferConfirm': 'यह ट्रांसफर अनुरोध हटाएं?',
      'stockTransfers': 'स्टॉक ट्रांसफर',
      'approve': 'स्वीकार',
      'reject': 'अस्वीकार',
      'category': 'श्रेणी',
      'design': 'डिज़ाइन',
      'transferDetails': 'ट्रांसफर विवरण',
      'transferSuccess': 'ट्रांसफर सफल',
      'transferFailed': 'ट्रांसफर विफल',
      'statusFilter': 'स्थिति फ़िल्टर',
      'selectAtLeastOneItem': 'कृपया कम से कम एक आइटम चुनें',
      'selectEmployee': 'कर्मचारी चुनें',
      'selectEmployeeError': 'कृपया एक कर्मचारी चुनें',
      'admin': 'एडमिन',
      'clearServerStockConfirm': 'क्या आप वाकई सर्वर से स्टॉक डेटा साफ़/हटाना चाहते हैं?',
    },
    'ar': {
      'settings': 'الإعدادات',
      'product': 'منتج',
      'inventory': 'المخزون',
      'search': 'بحث',
      'order': 'الطلب',
      'stockTransfer': 'نقل المخزون',
      'report': 'تقرير',
      'quotations': 'عروض الأسعار',
      'deliveryChallan': 'سند التسليم',
      'labelTodayRate': 'سعر اليوم',
      'sampleIn': 'عينة داخل',
      'sampleOut': 'عينة خارج',
      'home': 'الرئيسية',
      'logout': 'تسجيل الخروج',
      'account': 'الحساب',
      'usernamePassword': 'اسم المستخدم وكلمة المرور',
      'userPermission': 'صلاحيات المستخدم',
      'managePermission': 'إدارة الصلاحيات',
      'email': 'البريد الإلكتروني',
      'backup': 'نسخة احتياطية',
      'dataBackup': 'نسخ احتياطي للبيانات',
      'autoSync': 'مزامنة تلقائية',
      'enableAutomaticSync': 'تفعيل المزامنة التلقائية',
      'notifications': 'الإشعارات',
      'notificationSettings': 'إعدادات الإشعارات',
      'branches': 'الفروع',
      'branchManagement': 'إدارة الفروع',
      'customApi': 'API مخصص',
      'configureApiUrl': 'تكوين رابط API',
      'sheetUrl': 'رابط Sheet',
      'setGoogleSheetUrl': 'تعيين رابط Google Sheet',
      'stockTransferUrl': 'رابط نقل المخزون',
      'stockTransferApiUrl': 'رابط API لنقل المخزون',
      'clearData': 'مسح البيانات',
      'clearLocalData': 'مسح البيانات المحلية',
      'language': 'اللغة',
      'location': 'الموقع',
      'selectLanguage': 'اختر اللغة',
      'english': 'English',
      'hindi': 'Hindi',
      'arabic': 'العربية',
      'locationList': 'قائمة المواقع',
      'selectDate': 'اختر التاريخ',
      'headerSr': 'تسلسل',
      'date': 'التاريخ',
      'userId': 'UserId',
      'address': 'العنوان',
      'noLocationsFound': 'لم يتم العثور على مواقع',
      'failedToGetLocation': 'فشل في الحصول على الموقع',
      'back': 'رجوع',
      'cancel': 'إلغاء',
      'save': 'حفظ',
      'ok': 'موافق',
      'route': 'المسار',
      'defaultLoginEmail': 'البريد الافتراضي لتسجيل الدخول',
      'permissionsFromServer': 'يتم تعيين الصلاحيات من الخادم عند تسجيل الدخول.',
      'backupOptions': 'خيارات النسخ الاحتياطي',
      'backupChoose': 'اختر كيفية نسخ بياناتك احتياطياً.',
      'saveToDevice': 'حفظ على الجهاز',
      'sendViaEmail': 'إرسال عبر البريد',
      'restoreBackup': 'استعادة النسخة الاحتياطية',
      'autoSyncSettings': 'إعدادات المزامنة التلقائية',
      'syncInterval': 'فترة المزامنة:',
      'min15': '15 دقيقة',
      'min30': '30 دقيقة',
      'hour1': '1 ساعة',
      'hour24': '24 ساعة',
      'confirmClearData': 'تأكيد مسح البيانات',
      'clearDataMessage': 'سيؤدي هذا إلى حذف جميع بيانات التطبيق من هذا الجهاز نهائياً. هل تريد المتابعة؟',
      'continueLabel': 'متابعة',
      'verifyPassword': 'التحقق من كلمة المرور',
      'password': 'كلمة المرور',
      'incorrectPassword': 'كلمة مرور غير صحيحة',
      'enableNotifications': 'تفعيل الإشعارات',
      'usernameLabel': 'اسم المستخدم',
      'send': 'إرسال',
      'restoreComplete': 'اكتملت الاستعادة. أعد تشغيل التطبيق إذا لزم الأمر.',
      'backupFailed': 'فشل النسخ الاحتياطي',
      'savedTo': 'تم الحفظ',
      'selectedBranchIds': 'معرفات الفروع المحددة للمزامنة',
      'enterEmailAddress': 'أدخل عنوان البريد',
      'clearBtn': 'مسح',
      'viewLocationList': 'عرض قائمة المواقع',
      'enabled': 'مفعّل',
      'disabled': 'معطّل',
      'addSingleProduct': 'إضافة منتج واحد',
      'addBulkProducts': 'إضافة منتجات بالجملة',
      'editProduct': 'تعديل المنتج',
      'deleteProduct': 'حذف المنتج',
      'addBtn': 'إضافة',
      'delete': 'حذف',
      'reset': 'إعادة تعيين',
      'apply': 'تطبيق',
      'importBtn': 'استيراد',
      'done': 'تم',
      'filters': 'الفلاتر',
      'all': 'الكل',
      'actions': 'إجراءات',
      'listView': 'عرض القائمة',
      'gridView': 'عرض الشبكة',
      'exporting': 'جاري التصدير...',
      'exportPdf': 'تصدير PDF',
      'reportEmailBody': '<h2>إليك تقرير المسح الخاص بك</h2><p>التفاصيل مرفقة.</p>',
      'saveDetails': 'حفظ التفاصيل',
      'addNew': '➕ إضافة جديد',
      'failedToStartRfidScanner': 'فشل في تشغيل ماسح RFID',
      'pleaseSelectVendorCategoryProductDesignPurity': 'يرجى اختيار المورد والفئة والمنتج والتصميم والنقاء',
      'epcRequired': 'EPC مطلوب',
      'saved': 'تم الحفظ',
      'saveFailed': 'فشل الحفظ',
      'pleaseSelectCategoryProductDesign': 'يرجى اختيار الفئة والمنتج والتصميم',
      'itemsSavedSuccessfully': 'تم حفظ العناصر بنجاح',
      'failedToSaveItemsToServer': 'فشل حفظ العناصر على الخادم',
      'failedToClearServerStock': 'فشل مسح بيانات المخزون من الخادم',
      'deviceConfigNotFound': 'تعذر العثور على إعداد الجهاز / رمز العميل',
      'pleaseScanValidRfid': 'يرجى مسح علامة RFID / لا توجد بيانات EPC/RFID صالحة',
      'errorSavingData': 'خطأ في حفظ البيانات: {message}',
      'errorClearingData': 'خطأ في مسح البيانات: {message}',
      'recordsDeletedSuccess': 'تم حذف {count} سجل بنجاح',
      'failedToPrintPdf': 'فشل طباعة PDF: {error}',
      'failedToSaveFaceToServer': 'فشل حفظ بيانات الوجه على الخادم',
      'failedFieldsLabel': 'فشل: {fields}',
      'customApiUrlHint': 'https://your-api.com/',
      'selectOption': 'اختر {label}',
      'addScannedTagsBeforeSaving': 'أضف العلامات الممسوحة مع أكواد العناصر قبل الحفظ',
      'couldNotReadFile': 'تعذرت قراءة الملف',
      'noHeadersInExcel': 'لم يتم العثور على رؤوس في ملف Excel',
      'productUpdatedSuccessfully': 'تم تحديث المنتج بنجاح!',
      'failedToUpdateProduct': 'فشل تحديث المنتج.',
      'productDeletedSuccessfully': 'تم حذف المنتج بنجاح!',
      'noProductsToExport': 'لا توجد منتجات للتصدير.',
      'noProductsMatchingFilters': 'لم يتم العثور على منتجات مطابقة للفلاتر.',
      'tryResettingFilters': 'حاول إعادة تعيين الفلاتر أو استعلام البحث.',
      'apiActiveCannotEdit': 'هذا المنتج ApiActive ولا يمكن تعديله.',
      'nameRequired': 'الاسم مطلوب',
      'scanTagsToAddRows': 'امسح العلامات لإضافة صفوف',
      'errorWithMessage': 'خطأ: {message}',
      'errorPickingPhoto': 'خطأ في اختيار الصورة: {error}',
      'errorGeneratingPdf': 'خطأ في إنشاء PDF: {error}',
      'importSuccessful': 'تم الاستيراد بنجاح: {count} حقول',
      'importWithErrors': 'تم الاستيراد مع أخطاء: {errors}',
      'fieldsImportedProgress': '{imported} / {total} حقول مستوردة',
      'addType': 'إضافة {type}',
      'enterTypeName': 'أدخل اسم {type}',
      'confirmDeleteProduct': 'هل أنت متأكد من حذف المنتج "{name}" برمز العنصر: {code}؟',
      'tableView': 'عرض الجدول',
      'selectTableViewFields': 'اختر الحقول التي يجب أن تظهر في عرض الجدول',
      'mainFields': 'الحقول الرئيسية',
      'selectSheetFields': 'اختر حقول الورقة',
      'mapColumn': 'ربط العمود',
      'itemDetails': 'تفاصيل العنصر',
      'importingExcelData': 'جاري استيراد بيانات Excel',
      'generalDetails': 'التفاصيل العامة',
      'weights': 'الأوزان',
      'makingStonePricing': 'التصنيع وتسعير الأحجار',
      'rfidStoreDetails': 'تفاصيل RFID والمتجر',
      'productTitleName': 'عنوان / اسم المنتج',
      'pieces': 'القطع',
      'grossWeightG': 'الوزن الإجمالي (g)',
      'netWeightG': 'الوزن الصافي (g)',
      'stoneWeightG': 'وزن الحجر (g)',
      'diamondWeightG': 'وزن الماس (g)',
      'makingPerGram': 'التصنيع / جرام',
      'rfidTag': 'علامة RFID',
      'epcValueUhf': 'قيمة EPC (UHF)',
      'skuCode': 'رمز SKU',
      'branchName': 'اسم الفرع',
      'boxName': 'اسم الصندوق',
      'counterName': 'اسم العداد',
      'productName': 'اسم المنتج',
      'fieldEpc': 'EPC',
      'fieldVendor': 'المورد',
      'fieldSku': 'SKU',
      'fieldRfidCode': 'رمز RFID',
      'fieldCategory': 'الفئة',
      'fieldProduct': 'المنتج',
      'fieldDesign': 'التصميم',
      'fieldPurity': 'النقاء',
      'fieldGrossWeight': 'الوزن الإجمالي',
      'fieldStoneWeight': 'وزن الحجر',
      'fieldDiamondWeight': 'وزن الماس',
      'fieldNetWeight': 'الوزن الصافي',
      'fieldMakingGram': 'التصنيع/جرام',
      'fieldMakingPercent': 'التصنيع %',
      'fieldFixMaking': 'تصنيع ثابت',
      'fieldFixWastage': 'هدر ثابت',
      'fieldStoneAmount': 'مبلغ الحجر',
      'fieldDiamondAmount': 'مبلغ الماس',
      'itemCode': 'رمز العنصر',
      'rfidCode': 'رمز RFID',
      'searchSkuCodeName': 'بحث SKU، الرمز، الاسم...',
      'productListCount': 'قائمة المنتجات ({count})',
      'labelledStockReport': 'تقرير المخزون المُوسوم',
      'totalItems': 'إجمالي العناصر: {count}',
      'pageOf': 'صفحة {page} من {total}',
      'lblRfid': 'RFID',
      'lblCode': 'الرمز',
      'lblGrossWt': 'و. إ.',
      'lblNetWt': 'و. ص.',
      'lblStoneWt': 'و. ح.',
      'lblDiamondWt': 'و. م.',
      'colGrossWt': 'الوزن الإجمالي',
      'colStoneWt': 'وزن الحجر',
      'colDiamondWt': 'وزن الماس',
      'colNetWt': 'الوزن الصافي',
      'colStoneAmt': 'مبلغ الحجر',
      'colDiamondAmt': 'مبلغ الماس',
      'colRfid': 'RFID',
      'colSku': 'SKU',
      'colEpc': 'EPC',
      'colVendor': 'المورد',
      'camera': 'الكاميرا',
      'gallery': 'المعرض',
      'selectLabel': 'اختر {label}',
      'addLabel': 'إضافة {label}',
      'customerOrdersList': 'قائمة طلبات العملاء',
      'deleteOrder': 'حذف الطلب',
      'deleteOrderConfirm': 'هل أنت متأكد من حذف الطلب المخصص رقم #{id}؟',
      'searchOrderHint': 'البحث برقم الطلب أو العميل...',
      'orderDeletedSuccessfully': '✅ تم حذف الطلب المخصص بنجاح',
      'deliveryChallanList': 'قائمة إيصال التسليم',
      'searchChallanHint': 'البحث برقم الإيصال أو اسم العميل...',
      'noChallansFound': 'لم يتم العثور على إيصال تسليم',
      'confirmDeleteChallan': 'هل أنت متأكد من حذف إيصال التسليم هذا؟',
      'challanDeletedSuccessfully': '✅ تم حذف إيصال التسليم بنجاح',
      'noOrdersFound': 'لم يتم العثور على طلبات مخصصة',
      'walkInCustomer': 'عميل عابر',
      'headerOrderNo': 'رقم الطلب',
      'headerFineWt': 'الوزن النقي+',
      'headerTaxAmt': 'قيمة الضريبة',
      'headerTotalAmt': 'المبلغ الإجمالي',
      'createChallanHint': 'قم بإنشاء إيصال جديد بالضغط على زر +.',
      'headerChallanNo': 'رقم الإيصال',
      'welcomeTo': 'مرحباً بك في',
      'sparkleRfid': 'سباركل RFID',
      'pleaseLoginToContinue': 'يرجى تسجيل الدخول للمتابعة',
      'rememberMe': 'تذكرني',
      'forgotPassword': 'هل نسيت كلمة المرور؟',
      'useFaceDetectionLogin': 'استخدم التعرف على الوجه لمتابعة تسجيل الدخول',
      'logIn': 'تسجيل الدخول',
      'logInWithFace': 'تسجيل الدخول بالوجه',
      'troubleLogin': 'تواجه مشكلة في تسجيل الدخول؟ ',
      'contactUsClicked': 'تم النقر على اتصل بنا',
      'contactUs': 'اتصل بنا',
      'expiryWarning': 'تحذير انتهاء الصلاحية',
      'faceLogin': 'تسجيل الدخول بالوجه',
      'alignFaceInCircle': 'قم بمحاذاة وجهك داخل الدائرة',
      'scanningFace': 'جاري مسح الوجه...',
      'faceScanSimulationComplete': 'اكتملت محاكاة مسح الوجه. لم يتم تسجيل تسجيل الدخول بالوجه.',
      'fieldCustomerName': 'اسم العميل *',
      'fieldMobileNumber': 'رقم الهاتف المحمول *',
      'fieldEmailAddress': 'البريد الإلكتروني',
      'fieldPanNumber': 'رقم PAN',
      'fieldGstNumber': 'رقم ضريبة القيمة المضافة (GST)',
      'fieldStreetAddress': 'عنوان الشارع',
      'fieldCity': 'المدينة',
      'validationNameRequired': 'يرجى إدخال اسم العميل',
      'validationMobileRequired': 'يرجى إدخال رقم الهاتف المحمول',
      'validationMobileDigits': 'أدخل رقم هاتف محمول صالحاً مكوناً من 10 أرقام',
      'validationPanDigits': 'يجب أن يتكون PAN من 10 أحرف بالضبط',
      'validationGstDigits': 'يجب أن يتكون GST من 15 حرفاً بالضبط',
      'noLocalDataToExportSyncFirst': 'لا توجد بيانات محلية للتصدير. يرجى مزامنة البيانات أولاً.',
      'importExcel': 'استيراد\nإكسل',
      'exportExcel': 'تصدير\nإكسل',
      'syncData': 'مزامنة\nالبيانات',
      'scanToDesktop': 'مسح إلى\nسطح المكتب',
      'syncSheetData': 'مزامنة بيانات\nالورقة',
      'uploadDataToServer': 'تحميل البيانات\nإلى الخادم',
      'openProductList': 'فتح قائمة المنتجات',
      'exportingExcel': 'جاري تصدير إكسل...',
      'dataSyncSuccessfully': 'تم مزامنة البيانات بنجاح!',
      'showLess': 'عرض أقل',
      'addAtLeastOneItem': 'أضف عنصرًا واحدًا على الأقل لتعيين تفاصيل الطلب',
      'orderScreen': 'شاشة الطلب',
      'orderDetails': 'تفاصيل الطلب',
      'itemAmt': 'مبلغ العنصر',
      'confirmDeleteItem': 'هل أنت متأكد أنك تريد حذف هذا العنصر؟',
      'gstLabel': 'ضريبة السلع والخدمات 3.00%',
      'totalAmount': 'المبلغ الإجمالي',
      'orderSavedSuccessfully': 'تم حفظ الطلب بنجاح',
      'orderSavedOffline': 'تم حفظ الطلب دون اتصال — سيتم المزامنة عند توفر الإنترنت',
      'customerAddedOffline': 'تم حفظ العميل دون اتصال — سيتم المزامنة عند توفر الإنترنت',
      'orderPendingSync': 'في انتظار المزامنة',
      'syncOrdersNow': 'مزامنة الطلبات',
      'offlineOrderMode': 'وضع عدم الاتصال — بيانات مخزنة',
      'failedToSaveOrder': 'فشل في حفظ الطلب',
      'confirmDeleteChallanItem': 'هل أنت متأكد أنك تريد حذف هذا العنصر من السند؟',
      'challanFields': 'حقول السند',
      'itemName': 'اسم العميل *',
      'rate': 'السعر',
      'makingChg': 'رسوم الصياغة',
      'amount': 'المبلغ',
      'fineWt': 'الوزن الصافي',
      'editDeliveryChallan': 'تعديل سند التسليم',
      'createDeliveryChallan': 'إنشاء سند تسليم',
      'challanSavedSuccessfully': 'تم حفظ سند التسليم بنجاح',
      'challanUpdatedSuccessfully': 'تم تحديث سند التسليم بنجاح',
      'failedToSubmitChallan': 'فشل في تقديم سند التسليم',
      'quotationList': 'قائمة عروض الأسعار',
      'searchQuotationHint': 'البحث حسب رقم عرض السعر أو العميل...',
      'noQuotationsFound': 'لم يتم العثور على عروض أسعار',
      'headerQNo': 'رقم عرض السعر',
      'customerName': 'اسم العميل',
      'addAtLeastOneQuotationItem': 'أضف عنصرًا واحدًا على الأقل لتعيين تفاصيل عرض السعر',
      'quotationDetails': 'تفاصيل عرض السعر',
      'quotationSavedSuccessfully': 'تم حفظ عرض السعر بنجاح',
      'quotationUpdatedSuccessfully': 'تم تحديث عرض السعر بنجاح',
      'failedToSaveQuotation': 'فشل في حفظ عرض السعر',
      'ratesUpdatedSuccessfully': 'تم تحديث الأسعار بنجاح',
      'failedToUpdateRates': 'فشل في تحديث الأسعار',
      'noRatesFound': 'لم يتم العثور على أسعار',
      'todayRatePerGm': 'سعر اليوم / جرام',
      'searchError': 'خطأ في البحث: {error}',
      'noSearchableIdentifiersFound': 'لم يتم العثور على معرفات قابلة للبحث',
      'searchSampleOutHint': 'البحث عن رقم عينة الخارج أو اسم العميل...',
      'createSampleOutHint': 'قم بإنشاء عينة خارج جديدة باستخدام الزر +.',
      'returnTitle': 'إرجاع',
      'selectSampleOutNoFirst': 'يرجى تحديد رقم عينة الخارج أولاً',
      'confirmAddMatched': 'هل أنت متأكد من إضافة هذا العنصر إلى قائمة المطابقة؟',
      'no': 'لا',
      'yes': 'نعم',
      'itemAddedInMatchedList': 'تم إضافة العنصر إلى قائمة المطابقة',
      'confirmRemoveMatched': 'هل أنت متأكد من إزالة هذا العنصر من قائمة المطابقة؟',
      'itemsLabel': 'العناصر',
      'exportingProgress': 'جاري التصدير... {count} صفوف',
      'customOrderFields': 'حقول الطلب المخصص',
      'totalWeight': 'الوزن الإجمالي',
      'packingWt': 'وزن التعبئة',
      'ratePerGram': 'السعر لكل جرام',
      'colors': 'الألوان',
      'screwType': 'نوع المسمار',
      'polishType': 'نوع الصقل',
      'finePercent': 'نسبة النقاء %',
      'wastagePercent': 'نسبة الهدر %',
      'deliveryDate': 'تاريخ التسليم',
      'mrp': 'الحد الأقصى لسعر التجزئة',
      'colorType': 'نوع اللون',
      'selectBranch': 'اختر الفرع',
      'salesman': 'البائع',
      'pleaseSelectBranchAndDate': 'يرجى اختيار الفرع والتاريخ.',
      'orderDate': 'تاريخ الطلب',
      'enterExhibition': 'أدخل المعرض',
      'enterRemark': 'أدخل ملاحظة',
      'enterSize': 'أدخل الحجم',
      'enterLength': 'أدخل الطول',
      'enterFinePercentage': 'أدخل نسبة النقاء',
      'enterWastage': 'أدخل الهدر',
      'pleaseWaitItemsLoading': 'يرجى الانتظار، لا تزال العناصر قيد التحميل',
      'noItemsInCurrentScope': 'لا توجد عناصر في النطاق الحالي',
      'noRfidEpcInScope': 'لم يتم العثور على RFID/EPC على العناصر في هذا النطاق',
      'allItemsAlreadyMatched': 'جميع العناصر مطابقة بالفعل!',
      'previousScanRestored': 'تم استعادة المسح السابق',
      'allItemsMatchedScanStopped': 'تطابقت جميع العناصر. تم إيقاف المسح.',
      'scanResetSuccessful': 'تم إعادة ضبط المسح بنجاح',
      'size': 'الحجم',
      'length': 'الطول',
      'hallmarkAmt': 'مبلغ الدمغة',
      'finePlusWt': 'الوزن الصافي+',
      'remark': 'ملاحظة',
      'tapToEnter': 'انقر للإدخال…',
      'categoryFirst': 'الفئة أولاً',
      'productFirst': 'المنتج أولاً',
      'designFirst': 'التصميم أولاً',
      'selectVendorFirst': 'اختر المورد أولاً',
      'retry': 'إعادة المحاولة',
      'select': 'حدد',
      'import': 'استيراد',
      'box': 'صندوق',
      'item': 'العنصر',
      'tapTo': 'انقر لـ ',
      'chooseFile': 'اختيار ملف',
      'matched': 'مطابق',
      'unmatched': 'غير مطابقة',
      'formatsLabel': 'الصيغ: xls, xlsx',
      'maxFileSize': 'الحد الأقصى: 250 ميجابايت',
      'totalInv': 'إجمالي المخزون',
      'start': 'بدء',
      'end': 'نهاية',
      'totalQty': 'إجمالي الكمية',
      'match': 'مطابقة',
      'unmatch': 'غير مطابقة',
      'privacyPolicy': 'سياسة الخصوصية',
      'viewPrivacyPolicy': 'عرض سياسة الخصوصية الخاصة بنا',
      'faceData': 'بيانات الوجه',
      'addFaceLoginData': 'إضافة بيانات تسجيل الدخول بالوجه',
      'localWifiMode': 'وضع الواي فاي المحلي',
      'usingInternetConnection': 'باستخدام اتصال الإنترنت',
      'reusableTags': 'علامات قابلة لإعادة الاستخدام',
      'singleReusableEnabled': 'تم تمكين فردي + قابل لإعادة الاستخدام',
      'onlyWebReusableEnabled': 'تم تمكين علامة الويب القابلة لإعادة الاستخدام فقط',
      'faceMatchedSuccessfully': 'تم مطابقة الوجه بنجاح',
      'faceNotRecognised': 'لم يتم التعرف على الوجه',
      'noSavedFaceDataFound': 'لم يتم العثور على بيانات وجه محفوظة',
      'saveFaceLabel': 'حفظ الوجه',
      'faceDetectedLabel': 'تم اكتشاف الوجه',
      'noFaceDetectedLabel': 'لم يتم اكتشاف وجه',
      'faceModelNotLoaded': 'لم يتم تحميل نموذج الوجه',
      'cameraPermissionRequired': 'مطلوب إذن الكاميرا',
      'registerFace': 'تسجيل الوجه',
      'deviceIpNotFound': 'لم يتم العثور على عنوان IP للجهاز',
      'pleaseConnectToWifi': 'يرجى الاتصال بشبكة WiFi للوضع المحلي',
      'localWifiModeEnabledMsg': 'تم تمكين وضع الواي فاي المحلي',
      'internetModeEnabled': 'تم تمكين وضع الإنترنت',
      'trayMode': 'وضع الصينية',
      'trayModeDisabled': 'وضع المسدس اليدوي',
      'trayModeEnabledMsg': 'تم تمكين وضع الصينية',
      'trayModeDisabledMsg': 'تم تعطيل وضع الصينية',
      'selectTrayDevice': 'اختر الصينية عبر البلوتوث',
      'trayConnected': 'متصل',
      'trayNotConnected': 'غير متصل',
      'trayDeviceSelected': 'تم اختيار جهاز الصينية',
      'bluetoothPermissionRequired': 'مطلوب إذن البلوتوث لقارئ RFID عبر البلوتوث',
      'noBondedBluetoothDevices': 'لم يتم العثور على أجهزة RFID بلوتوث. شغّل القارئ وحاول مرة أخرى.',
      'r6Mode': 'وضع R6 بلوتوث',
      'r6ModeDisabled': 'إيقاف',
      'r6ModeEnabledMsg': 'تم تمكين وضع R6',
      'r6ModeDisabledMsg': 'تم تعطيل وضع R6',
      'selectR6Device': 'اختر Chainway R6',
      'r6DeviceSelected': 'تم اختيار جهاز R6',
      'loginErrorLabel': 'خطأ في تسجيل الدخول',
      'transferType': 'نوع النقل',
      'from': 'من',
      'to': 'إلى',
      'stockRequests': 'طلبات المخزون',
      'inRequest': 'طلب وارد',
      'outRequest': 'طلب صادر',
      'itemCodeOrRfid': 'رمز الصنف / RFID',
      'itemCodeLabel': 'رمز الصنف',
      'selectedQty': 'الكمية المحددة',
      'selectItemsToTransfer': 'اختر العناصر للنقل',
      'transferPreview': 'معاينة النقل',
      'submitTransfer': 'إرسال النقل',
      'transferredBy': 'نقل بواسطة',
      'transferredTo': 'نقل إلى',
      'remarks': 'ملاحظات',
      'pending': 'معلق',
      'approved': 'موافق',
      'rejected': 'مرفوض',
      'lost': 'مفقود',
      'transferBy': 'نقل بواسطة',
      'transferToCol': 'نقل إلى',
      'deleteTransferConfirm': 'حذف طلب النقل هذا؟',
      'stockTransfers': 'نقل المخزون',
      'approve': 'موافقة',
      'reject': 'رفض',
      'category': 'الفئة',
      'design': 'التصميم',
      'transferDetails': 'تفاصيل النقل',
      'transferSuccess': 'تم النقل بنجاح',
      'transferFailed': 'فشل النقل',
      'statusFilter': 'تصفية الحالة',
      'selectAtLeastOneItem': 'يرجى تحديد عنصر واحد على الأقل',
      'selectEmployee': 'اختر الموظف',
      'selectEmployeeError': 'يرجى اختيار موظف',
      'admin': 'المسؤول',
      'clearServerStockConfirm': 'هل أنت متأكد أنك تريد مسح/حذف بيانات المخزون من الخادم؟',
      'unknown': 'غير معروف',
      'mobileLabel': 'الجوال: {mobile}',
      'mobileGstLabel': 'الجوال: {mobile} | GST: {gst}',
      'selectSampleOutNoToLoadItems': 'اختر رقم عينة الخارج لتحميل العناصر',
    },
  };
}
