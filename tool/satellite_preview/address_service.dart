import 'dart:convert';

import 'package:bugman_graphs/models/trace_geometry.dart';
import 'package:bugman_graphs/services/address_suggestion_service.dart';
import 'package:bugman_graphs/services/address_suggestion_service_stub.dart';
import 'package:http/http.dart' as http;

/// Used only by the standalone preview. Never calls authenticated OpsBrain APIs.
class PreviewAddressService implements AddressSuggestionService {
  PreviewAddressService({http.Client? client, Uri? origin})
      : _client = client ?? http.Client(),
        _origin = origin ?? Uri.base;

  final http.Client _client;
  final Uri _origin;
  final _selections = <String, AddressSelection>{};

  @override
  Future<List<AddressSuggestion>> suggest(String query,
      {required String sessionToken}) async {
    final uri = _origin
        .resolve('/api/preview/address-search')
        .replace(queryParameters: {'address': query.trim()});
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 25));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw AddressSuggestionServiceException(payload['error']?.toString() ??
          'Address search is unavailable. Try again.');
    }
    final suggestions = <AddressSuggestion>[];
    for (final match in (payload['matches'] as List? ?? const [])) {
      final value = Map<String, dynamic>.from(match as Map);
      final address = value['address'] as String;
      final latitude = (value['latitude'] as num).toDouble();
      final longitude = (value['longitude'] as num).toDouble();
      final id = '$address|$latitude,$longitude';
      _selections[id] = AddressSelection(
        standardizedAddress: address,
        coordinate: GeoPoint(latitude: latitude, longitude: longitude),
        quality: const AddressQuality(
          geocodeGranularity: 'RANGE_INTERPOLATED',
          validationGranularity: 'OTHER',
          isPropertyLevel: false,
          addressComplete: false,
          requiresReview: true,
        ),
      );
      suggestions.add(AddressSuggestion(
          id: id,
          address: address,
          primaryText: address,
          secondaryText:
              'North Carolina · approximate Census address location'));
    }
    while (_selections.length > 50) {
      _selections.remove(_selections.keys.first);
    }
    return suggestions;
  }

  @override
  Future<AddressSelection> select(AddressSuggestion suggestion,
      {required String sessionToken}) async {
    final selection = _selections[suggestion.id];
    if (selection == null) {
      throw const AddressSuggestionServiceException(
          'Search the address again.');
    }
    return selection;
  }

  void dispose() => _client.close();
}
