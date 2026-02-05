import 'dart:async';
import 'package:flutter/material.dart';
import '../services/geocoding_service.dart';
import '../app_theme.dart';

/// Result returned when a place is selected
class PlaceSelection {
  final String address;
  final double lat;
  final double lng;
  final String? barrio;

  PlaceSelection({
    required this.address,
    required this.lat,
    required this.lng,
    this.barrio,
  });
}

/// A text field with Google Places autocomplete suggestions.
/// Calls the geocode-address Edge Function for suggestions.
class PlacesAutocompleteField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? initialValue;
  final ValueChanged<PlaceSelection> onPlaceSelected;
  final String? Function(String?)? validator;

  const PlacesAutocompleteField({
    super.key,
    this.labelText = 'Ubicacion',
    this.hintText = 'Escribe una direccion...',
    this.initialValue,
    required this.onPlaceSelected,
    this.validator,
  });

  @override
  State<PlacesAutocompleteField> createState() =>
      _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();

  List<PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  bool _ignoreNextChange = false;
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay to allow tap on suggestion to register
      Future.delayed(const Duration(milliseconds: 200), () {
        _removeOverlay();
      });
    }
  }

  void _onTextChanged() {
    if (_ignoreNextChange) {
      _ignoreNextChange = false;
      return;
    }

    _debounce?.cancel();
    final text = _controller.text.trim();

    if (text.length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      _removeOverlay();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(text);
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isLoading = true);

    final results = await geocodingService.autocomplete(input);

    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _isLoading = false;
      _showSuggestions = results.isNotEmpty;
    });

    if (_showSuggestions) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    _removeOverlay();
    _ignoreNextChange = true;
    _controller.text = suggestion.description;

    setState(() {
      _showSuggestions = false;
      _isLoading = true;
    });

    final details = await geocodingService.getPlaceDetails(suggestion.placeId);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (details != null) {
      widget.onPlaceSelected(PlaceSelection(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        barrio: details.barrio,
      ));
    }
  }

  void _showOverlay() {
    _removeOverlay();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return InkWell(
                    onTap: () => _selectSuggestion(suggestion),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 20, color: AppColors.textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  suggestion.mainText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                if (suggestion.secondaryText.isNotEmpty)
                                  Text(
                                    suggestion.secondaryText,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
          suffixIcon: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                )
              : const Icon(Icons.location_on_outlined),
        ),
        validator: widget.validator,
      ),
    );
  }
}
