import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/place.dart';
import '../features/map/map_page.dart';
import '../features/search/search_page.dart';
import '../features/saved/saved_page.dart';
import '../features/place_detail/place_detail_page.dart';
import 'app_shell.dart';

final router = GoRouter(
  initialLocation: '/map',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        // NOTE: MapPage in this project may not have a const unnamed constructor.
        // Use non-const instantiation to be safe.
        GoRoute(path: '/map', builder: (_, __) => MapPage()),
        GoRoute(path: '/search', builder: (_, __) => const SearchPage()),
        GoRoute(path: '/saved', builder: (_, __) => const SavedPage()),
      ],
    ),
    GoRoute(
      path: '/place',
      builder: (context, state) {
        final place = state.extra as Place;
        return PlaceDetailPage(place: place);
      },
    ),
  ],
);
