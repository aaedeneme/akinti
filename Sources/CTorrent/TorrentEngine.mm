#import "TorrentEngine.h"

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/load_torrent.hpp>

#include <memory>
#include <mutex>
#include <sstream>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

@implementation TETorrent
@end
@implementation TEFile
@end

static NSString *HashString(lt::info_hash_t const &h) {
    std::stringstream ss;
    ss << h.get_best();
    return [NSString stringWithUTF8String:ss.str().c_str()];
}

static NSError *MakeError(NSString *msg) {
    return [NSError errorWithDomain:@"Akinti" code:1 userInfo:@{NSLocalizedDescriptionKey: msg}];
}

@implementation TorrentEngine {
    std::unique_ptr<lt::session> _session;
    NSString *_stateDir;
    std::mutex _mutex;
}

- (instancetype)initWithStateDirectory:(NSString *)directory {
    if ((self = [super init])) {
        _stateDir = [directory copy];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        lt::settings_pack sp;
        sp.set_str(lt::settings_pack::user_agent, "Akinti/1.0");
        sp.set_int(lt::settings_pack::alert_mask, lt::alert_category::status | lt::alert_category::error);
        _session = std::make_unique<lt::session>(sp);
        [self loadSavedTorrents];
    }
    return self;
}

- (void)loadSavedTorrents {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_stateDir error:nil];
    for (NSString *item in items) {
        if (![item.pathExtension isEqualToString:@"resume"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:[_stateDir stringByAppendingPathComponent:item]];
        if (!data.length) continue;
        lt::error_code ec;
        lt::add_torrent_params p = lt::read_resume_data(
            lt::span<char const>((char const *)data.bytes, (int)data.length), ec);
        if (ec) continue;
        _session->async_add_torrent(std::move(p));
    }
}

- (BOOL)addMagnet:(NSString *)uri savePath:(NSString *)path error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params p = lt::parse_magnet_uri(std::string(uri.UTF8String), ec);
    if (ec) {
        if (error) *error = MakeError(@"Geçersiz magnet bağlantısı");
        return NO;
    }
    p.save_path = path.UTF8String;
    _session->async_add_torrent(std::move(p));
    return YES;
}

- (BOOL)addTorrentFile:(NSString *)file savePath:(NSString *)path error:(NSError **)error {
    try {
        lt::add_torrent_params p = lt::load_torrent_file(std::string(file.UTF8String));
        p.save_path = path.UTF8String;
        _session->async_add_torrent(std::move(p));
        return YES;
    } catch (std::exception const &e) {
        if (error) *error = MakeError([NSString stringWithUTF8String:e.what()]);
        return NO;
    }
}

- (lt::torrent_handle)handleFor:(NSString *)hash {
    for (auto const &h : _session->get_torrents()) {
        if ([HashString(h.info_hashes()) isEqualToString:hash]) return h;
    }
    return lt::torrent_handle();
}

- (void)pause:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause();
}

- (void)resume:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

- (void)forceStart:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

- (void)move:(NSString *)infoHash toPath:(NSString *)path {
    auto h = [self handleFor:infoHash];
    if (h.is_valid()) h.move_storage(std::string(path.UTF8String));
}

- (void)recheck:(NSString *)infoHash {
    auto h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_recheck();
}

- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles {
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    _session->remove_torrent(h, deleteFiles ? lt::session::delete_files : lt::remove_flags_t{});
    NSString *file = [_stateDir stringByAppendingPathComponent:[infoHash stringByAppendingString:@".resume"]];
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
}

- (void)setDownloadLimit:(int)down uploadLimit:(int)up {
    lt::settings_pack sp;
    sp.set_int(lt::settings_pack::download_rate_limit, down);
    sp.set_int(lt::settings_pack::upload_rate_limit, up);
    _session->apply_settings(sp);
}

- (NSArray<TETorrent *> *)snapshot {
    NSMutableArray *out = [NSMutableArray array];
    for (auto const &h : _session->get_torrents()) {
        lt::torrent_status st = h.status();
        TETorrent *t = [TETorrent new];
        t.infoHash = HashString(st.info_hashes);
        t.name = st.name.empty() ? t.infoHash : [NSString stringWithUTF8String:st.name.c_str()];
        t.savePath = [NSString stringWithUTF8String:st.save_path.c_str()];
        t.progress = st.progress;
        t.totalSize = st.total_wanted;
        t.downloaded = st.all_time_download;
        t.uploaded = st.all_time_upload;
        t.downloadRate = st.download_payload_rate;
        t.uploadRate = st.upload_payload_rate;
        t.peers = st.num_peers;
        t.seeds = st.num_seeds;
        t.errorMessage = @"";

        if (st.errc) {
            t.state = TEStateError;
            t.errorMessage = [NSString stringWithUTF8String:st.errc.message().c_str()];
        } else if (st.flags & lt::torrent_flags::paused) {
            t.state = TEStatePaused;
        } else {
            switch (st.state) {
                case lt::torrent_status::checking_files:
                case lt::torrent_status::checking_resume_data: t.state = TEStateChecking; break;
                case lt::torrent_status::downloading_metadata: t.state = TEStateMetadata; break;
                case lt::torrent_status::finished:
                case lt::torrent_status::seeding: t.state = TEStateSeeding; break;
                default: t.state = TEStateDownloading; break;
            }
        }
        [out addObject:t];
    }
    return out;
}

- (NSArray<TEFile *> *)filesFor:(NSString *)infoHash {
    NSMutableArray *out = [NSMutableArray array];
    auto h = [self handleFor:infoHash];
    if (!h.is_valid()) return out;
    auto ti = h.torrent_file();
    if (!ti) return out;
    std::vector<std::int64_t> prog = h.file_progress(lt::torrent_handle::piece_granularity);
    lt::file_storage const &fs = ti->files();
    for (int i = 0; i < fs.num_files(); ++i) {
        lt::file_index_t idx(i);
        TEFile *f = [TEFile new];
        f.path = [NSString stringWithUTF8String:fs.file_path(idx).c_str()];
        f.size = fs.file_size(idx);
        f.progress = (f.size > 0 && i < (int)prog.size()) ? (double)prog[i] / (double)f.size : 1.0;
        [out addObject:f];
    }
    return out;
}

- (void)saveState {
    std::lock_guard<std::mutex> lock(_mutex);
    int pending = 0;
    for (auto const &h : _session->get_torrents()) {
        auto st = h.status();
        if (!st.need_save_resume) continue;
        h.save_resume_data(lt::torrent_handle::save_info_dict);
        ++pending;
    }
    while (pending > 0) {
        if (!_session->wait_for_alert(lt::seconds(5))) break;
        std::vector<lt::alert *> alerts;
        _session->pop_alerts(&alerts);
        for (lt::alert *a : alerts) {
            if (auto *rd = lt::alert_cast<lt::save_resume_data_alert>(a)) {
                std::vector<char> buf = lt::write_resume_data_buf(rd->params);
                NSString *name = [HashString(rd->params.info_hashes) stringByAppendingString:@".resume"];
                NSData *data = [NSData dataWithBytes:buf.data() length:buf.size()];
                [data writeToFile:[_stateDir stringByAppendingPathComponent:name] atomically:YES];
                --pending;
            } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
                --pending;
            }
        }
    }
}

@end
