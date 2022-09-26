import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

// import '../../channels/channel_video.dart';
import '../../exceptions/exceptions.dart';
import '../../extensions/helpers_extension.dart';
import '../../playlists/playlist.dart';
import '../../retry.dart';
import '../../playlists/playlists.dart';
import '../../common/engagement.dart';
import '../../common/thumbnail_set.dart';
import '../../common/thumbnail.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';
import '../youtube_http_client.dart';

///
class ChannelPlaylistPage extends YoutubePage<_InitialData> {
  ///
  final String channelId;

  late final List<Playlist> playlist = initialData.uploads;

  /// InitialData
  ChannelPlaylistPage.id(this.channelId, _InitialData? initialData)
      : super(null, null, initialData);

  ///
  Future<ChannelPlaylistPage?> nextPage(YoutubeHttpClient httpClient) async {
    if (initialData.token.isEmpty) {
      return null;
    }

    final data = await httpClient.sendPost('browse', initialData.token);
    return ChannelPlaylistPage.id(channelId, _InitialData(data));
  }

  ///
  static Future<ChannelPlaylistPage> get(
      YoutubeHttpClient httpClient, String channelId) {
    var url = 'https://www.youtube.com/channel/$channelId/playlists';
    return retry(httpClient, () async {
      var raw = await httpClient.getString(url);
      return ChannelPlaylistPage.parse(raw, channelId);
    });
  }

  ///
  ChannelPlaylistPage.parse(String raw, this.channelId)
      : super(parser.parse(raw), (root) => _InitialData(root));
}

class _InitialData extends InitialData {
  _InitialData(JsonMap root) : super(root);

  late final JsonMap? continuationContext = getContinuationContext();

  late final String token = continuationContext?.getT<String>('token') ?? '';

  late final List<Playlist> uploads = _getUploads();

  List<Playlist> _getUploads() {
    final content = getContentContext();
    if (content.isEmpty) {
      return const <Playlist>[];
    }
    return content.map(_parseContent).whereNotNull().toList();
  }

  List<JsonMap> getContentContext() {
    List<JsonMap>? context;
    if (root.containsKey('contents')) {
      final render = root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.map((e) => e['tabRenderer'])
          .cast<JsonMap>()
          .firstWhereOrNull((e) => e['selected'] as bool? ?? false)
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.firstOrNull;

      if (render?.containsKey('gridRenderer') ?? false) {
        context =
            render?.get('gridRenderer')?.getList('items')?.cast<JsonMap>();
      } else if (render?.containsKey('shelfRenderer') ?? false) {
        context = render
            ?.get('shelfRenderer')
            ?.get('content')
            ?.get('horizontalListRenderer')
            ?.getList('items')
            ?.cast<JsonMap>();
      } else if (render?.containsKey('messageRenderer') ?? false) {
        // Workaround for no-videos.
        context = const [];
      }
    }
    if (context == null && root.containsKey('onResponseReceivedActions')) {
      context = root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.cast<JsonMap>();
    }
    if (context == null) {
      throw FatalFailureException('Failed to get initial data context.', 0);
    }
    return context;
  }

  JsonMap? getContinuationContext() {
    if (root.containsKey('contents')) {
      return root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.map((e) => e['tabRenderer'])
          .cast<JsonMap>()
          .firstWhereOrNull((e) => e['selected'] as bool)
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('gridRenderer')
          ?.getList('items')
          ?.firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand');
    }
    if (root.containsKey('onResponseReceivedActions')) {
      return root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand');
    }
    return null;
  }

  Playlist? _parseContent(JsonMap? content) {
    if (content == null || !content.containsKey('gridPlaylistRenderer')) {
      return null;
    }

    var playlist = content.get('gridPlaylistRenderer')!;
    return Playlist(
        PlaylistId(playlist.getT<String>('playlistId')!),
        playlist.get('title')?.getT<String>('simpleText') ??
            playlist
                .get('title')
                ?.getList('runs')
                ?.map((e) => e['text'])
                .join() ??
            '',
        '',
        '',
        ThumbnailSet(playlist.getT<String>('playlistId')!),
        Thumbnail(
            Uri.parse(playlist
                    .get('thumbnail')
                    ?.getList('thumbnails')
                    ?.last
                    .getT<String>('url') ??
                ''),
            playlist
                    .get('thumbnail')
                    ?.getList('thumbnails')
                    ?.last
                    .getT<int>('height') ??
                0,
            playlist
                    .get('thumbnail')
                    ?.getList('thumbnails')
                    ?.last
                    .getT<int>('width') ??
                0),
        Engagement(
          playlist
                  .get('videoCountText')
                  ?.getList('runs')
                  ?.first
                  .getT<String>('text')
                  .parseInt() ??
              0,
          null,
          null,
        ),
        playlist
                .get('videoCountText')
                ?.getList('runs')
                ?.first
                .getT<String>('text')
                .parseInt() ??
            0);
  }
}

//
