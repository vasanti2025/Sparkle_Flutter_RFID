import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../viewmodels/product_view_model.dart';

class EditProductScreen extends StatefulWidget {
  const EditProductScreen({super.key});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  
  bool _initialized = false;
  late BulkItem _originalItem;

  // Form Fields
  late TextEditingController _nameController;
  late TextEditingController _itemCodeController;
  late TextEditingController _rfidController;
  late TextEditingController _gwtController;
  late TextEditingController _swtController;
  late TextEditingController _dwtController;
  late TextEditingController _nwtController;
  late TextEditingController _categoryController;
  late TextEditingController _designController;
  late TextEditingController _purityController;
  late TextEditingController _makingGramController;
  late TextEditingController _makingPercentController;
  late TextEditingController _fixMakingController;
  late TextEditingController _fixWastageController;
  late TextEditingController _stoneAmtController;
  late TextEditingController _diamondAmtController;
  late TextEditingController _skuController;
  late TextEditingController _epcController;
  late TextEditingController _vendorController;
  late TextEditingController _branchNameController;
  late TextEditingController _boxNameController;
  late TextEditingController _pcsController;

  String? _localImagePath;
  bool _isSaving = false;

  @override
  void dispose() {
    if (_initialized) {
      _nameController.dispose();
      _itemCodeController.dispose();
      _rfidController.dispose();
      _gwtController.dispose();
      _swtController.dispose();
      _dwtController.dispose();
      _nwtController.dispose();
      _categoryController.dispose();
      _designController.dispose();
      _purityController.dispose();
      _makingGramController.dispose();
      _makingPercentController.dispose();
      _fixMakingController.dispose();
      _fixWastageController.dispose();
      _stoneAmtController.dispose();
      _diamondAmtController.dispose();
      _skuController.dispose();
      _epcController.dispose();
      _vendorController.dispose();
      _branchNameController.dispose();
      _boxNameController.dispose();
      _pcsController.dispose();
    }
    super.dispose();
  }

  void _initFields(BulkItem item) {
    if (_initialized) return;
    _originalItem = item;
    
    _nameController = TextEditingController(text: item.productName);
    _itemCodeController = TextEditingController(text: item.itemCode);
    _rfidController = TextEditingController(text: item.rfid);
    _gwtController = TextEditingController(text: item.grossWeight);
    _swtController = TextEditingController(text: item.stoneWeight);
    _dwtController = TextEditingController(text: item.diamondWeight);
    _nwtController = TextEditingController(text: item.netWeight);
    _categoryController = TextEditingController(text: item.category);
    _designController = TextEditingController(text: item.design);
    _purityController = TextEditingController(text: item.purity);
    _makingGramController = TextEditingController(text: item.makingPerGram);
    _makingPercentController = TextEditingController(text: item.makingPercent);
    _fixMakingController = TextEditingController(text: item.fixMaking);
    _fixWastageController = TextEditingController(text: item.fixWastage);
    _stoneAmtController = TextEditingController(text: item.stoneAmount);
    _diamondAmtController = TextEditingController(text: item.diamondAmount);
    _skuController = TextEditingController(text: item.sku);
    _epcController = TextEditingController(text: item.epc);
    _vendorController = TextEditingController(text: item.vendor);
    _branchNameController = TextEditingController(text: item.branchName);
    _boxNameController = TextEditingController(text: item.boxName);
    _pcsController = TextEditingController(text: item.pcs.toString());

    _initialized = true;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (photo != null) {
        setState(() {
          _localImagePath = photo.path;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('errorPickingPhoto', args: {'error': '$e'}))),
      );
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final s = context.s;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Color(0xFF5231A7)),
                title: Text(s.tr('camera'), style: GoogleFonts.poppins()),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFFD32940)),
                title: Text(s.tr('gallery'), style: GoogleFonts.poppins()),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isSaving = true;
    });

    final viewModel = Provider.of<ProductViewModel>(context, listen: false);

    // Build the updated BulkItem object
    final updatedItem = BulkItem(
      id: _originalItem.id,
      bulkItemId: _originalItem.bulkItemId,
      productName: _nameController.text.trim(),
      itemCode: _itemCodeController.text.trim(),
      rfid: _rfidController.text.trim(),
      grossWeight: _gwtController.text.trim(),
      stoneWeight: _swtController.text.trim(),
      diamondWeight: _dwtController.text.trim(),
      netWeight: _nwtController.text.trim(),
      category: _categoryController.text.trim(),
      design: _designController.text.trim(),
      purity: _purityController.text.trim(),
      makingPerGram: _makingGramController.text.trim(),
      makingPercent: _makingPercentController.text.trim(),
      fixMaking: _fixMakingController.text.trim(),
      fixWastage: _fixWastageController.text.trim(),
      stoneAmount: _stoneAmtController.text.trim(),
      diamondAmount: _diamondAmtController.text.trim(),
      sku: _skuController.text.trim(),
      epc: _epcController.text.trim(),
      vendor: _vendorController.text.trim(),
      tid: _originalItem.tid,
      box: _originalItem.box,
      designCode: _originalItem.designCode,
      productCode: _originalItem.productCode,
      imageUrl: _originalItem.imageUrl,
      totalQty: _originalItem.totalQty,
      pcs: int.tryParse(_pcsController.text) ?? _originalItem.pcs,
      matchedPcs: _originalItem.matchedPcs,
      totalGwt: double.tryParse(_gwtController.text) ?? _originalItem.totalGwt,
      matchGwt: _originalItem.matchGwt,
      totalStoneWt: double.tryParse(_swtController.text) ?? _originalItem.totalStoneWt,
      matchStoneWt: _originalItem.matchStoneWt,
      totalNetWt: double.tryParse(_nwtController.text) ?? _originalItem.totalNetWt,
      matchNetWt: _originalItem.matchNetWt,
      unmatchedQty: _originalItem.unmatchedQty,
      matchedQty: _originalItem.matchedQty,
      unmatchedGrossWt: _originalItem.unmatchedGrossWt,
      mrp: _originalItem.mrp,
      counterName: _originalItem.counterName,
      counterId: _originalItem.counterId,
      boxId: _originalItem.boxId,
      boxName: _boxNameController.text.trim(),
      branchId: _originalItem.branchId,
      branchName: _branchNameController.text.trim(),
      packetId: _originalItem.packetId,
      packetName: _originalItem.packetName,
      scannedStatus: _originalItem.scannedStatus,
      categoryId: _originalItem.categoryId,
      productId: _originalItem.productId,
      branchType: _originalItem.branchType,
      designId: _originalItem.designId,
      isScanned: _originalItem.isScanned,
      totalWt: _originalItem.totalWt,
      categoryWt: _originalItem.categoryWt,
      skuId: _originalItem.skuId,
      purityId: _originalItem.purityId,
      status: _originalItem.status,
    );

    final success = await viewModel.updateProductItem(updatedItem, _localImagePath);
    
    setState(() {
      _isSaving = false;
    });

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${context.sRead.tr('productUpdatedSuccessfully')}')),
      );
      Navigator.pop(context, true);
    } else {
      if (!mounted) return;
      final errorMsg = viewModel.errorMessage ?? context.sRead.tr('failedToUpdateProduct');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${context.sRead.tr('errorWithMessage', args: {'message': errorMsg})}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final BulkItem item = ModalRoute.of(context)!.settings.arguments as BulkItem;
    _initFields(item);

    final isApiActiveItem = item.status.toLowerCase() == 'apiactive';
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              s.editProduct,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? screenWidth * 0.15 : 16,
              vertical: 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ApiActive status banner
                  if (isApiActiveItem) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.apiActiveCannotEdit,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.orange[900],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Profile-style Product Image Picker
                  Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color.fromRGBO(0, 0, 0, 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _buildProductImage(item),
                        ),
                      ),
                      if (!isApiActiveItem)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFFD32940),
                            radius: 18,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                              onPressed: _showImageSourceSheet,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Cards with Form Fields
                  _buildFormCard(
                    title: s.generalDetails,
                    icon: Icons.info_outline,
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: s.productTitleName,
                        enabled: !isApiActiveItem,
                        validator: (v) => v!.isEmpty ? s.nameRequired : null,
                      ),
                      _buildTextField(
                        controller: _itemCodeController,
                        label: s.itemCode,
                        enabled: false, // Item code is read-only
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _categoryController,
                              label: s.fieldCategory,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _designController,
                              label: s.fieldDesign,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _purityController,
                              label: s.fieldPurity,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _pcsController,
                              label: s.pieces,
                              keyboardType: TextInputType.number,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  _buildFormCard(
                    title: s.weights,
                    icon: Icons.monitor_weight_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _gwtController,
                              label: s.grossWeightG,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _nwtController,
                              label: s.netWeightG,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _swtController,
                              label: s.stoneWeightG,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _dwtController,
                              label: s.diamondWeightG,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  _buildFormCard(
                    title: s.makingStonePricing,
                    icon: Icons.currency_rupee,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _makingGramController,
                              label: s.makingPerGram,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _makingPercentController,
                              label: s.fieldMakingPercent,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _fixMakingController,
                              label: s.fieldFixMaking,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _fixWastageController,
                              label: s.fieldFixWastage,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _stoneAmtController,
                              label: s.fieldStoneAmount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _diamondAmtController,
                              label: s.fieldDiamondAmount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  _buildFormCard(
                    title: s.rfidStoreDetails,
                    icon: Icons.nfc_outlined,
                    children: [
                      _buildTextField(
                        controller: _rfidController,
                        label: s.rfidTag,
                        enabled: !isApiActiveItem,
                      ),
                      _buildTextField(
                        controller: _epcController,
                        label: s.epcValueUhf,
                        enabled: !isApiActiveItem,
                      ),
                      _buildTextField(
                        controller: _skuController,
                        label: s.skuCode,
                        enabled: !isApiActiveItem,
                      ),
                      _buildTextField(
                        controller: _vendorController,
                        label: s.fieldVendor,
                        enabled: !isApiActiveItem,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _branchNameController,
                              label: s.branchName,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _boxNameController,
                              label: s.boxName,
                              enabled: !isApiActiveItem,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actions Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: Color(0xFF5231A7), width: 1.5),
                          ),
                          child: Text(
                            s.cancel,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF5231A7),
                            ),
                          ),
                        ),
                      ),
                      if (!isApiActiveItem) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveProduct,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      s.saveDetails,
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(BulkItem item) {
    if (_localImagePath != null) {
      return Image.file(File(_localImagePath!), fit: BoxFit.cover);
    }
    
    if (item.imageUrl.isNotEmpty) {
      final baseUrl = 'https://rrgold.loyalstring.co.in/';
      var storedUrl = item.imageUrl.trim();
      if (storedUrl.endsWith(',')) {
        storedUrl = storedUrl.substring(0, storedUrl.length - 1).trim();
      }
      String finalUrl;
      
      if (storedUrl.startsWith('http://') || storedUrl.startsWith('https://')) {
        finalUrl = storedUrl;
      } else {
        // Splitting by comma if there are multiple images
        final imgList = storedUrl.split(',');
        final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
        finalUrl = '$baseUrl$lastImg';
      }

      return Image.network(
        finalUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.image, color: Colors.grey, size: 50);
        },
      );
    }
    
    return const Icon(Icons.image, color: Colors.grey, size: 50);
  }

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      color: Colors.white,
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF5231A7)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        validator: validator,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[350]!),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          fillColor: enabled ? Colors.white : Colors.grey[50],
          filled: true,
        ),
      ),
    );
  }
}
