#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TEState) {
    TEStateChecking,
    TEStateMetadata,
    TEStateDownloading,
    TEStateSeeding,
    TEStatePaused,
    TEStateError,
};

@interface TETorrent : NSObject
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic) TEState state;
@property (nonatomic) double progress;
@property (nonatomic) int64_t totalSize;
@property (nonatomic) int64_t downloaded;
@property (nonatomic) int64_t uploaded;
@property (nonatomic) int downloadRate;
@property (nonatomic) int uploadRate;
@property (nonatomic) int peers;
@property (nonatomic) int seeds;
@end

@interface TEFile : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int64_t size;
@property (nonatomic) double progress;
@end

@interface TorrentEngine : NSObject
- (instancetype)initWithStateDirectory:(NSString *)directory;
- (BOOL)addMagnet:(NSString *)uri savePath:(NSString *)path error:(NSError **)error;
- (BOOL)addTorrentFile:(NSString *)file savePath:(NSString *)path error:(NSError **)error;
- (void)pause:(NSString *)infoHash;
- (void)resume:(NSString *)infoHash;
- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles;
- (void)recheck:(NSString *)infoHash;
/// Kuyruk sınırlarını yok sayarak hemen başlatır.
- (void)forceStart:(NSString *)infoHash;
/// İndirilen dosyaları yeni klasöre taşır.
- (void)move:(NSString *)infoHash toPath:(NSString *)path;
/// Bayt/sn. 0 = sınırsız.
- (void)setDownloadLimit:(int)down uploadLimit:(int)up;
- (NSArray<TETorrent *> *)snapshot;
- (NSArray<TEFile *> *)filesFor:(NSString *)infoHash;
/// Devam verilerini diske yazar (çıkışta ve periyodik olarak çağrılır).
- (void)saveState;
@end

NS_ASSUME_NONNULL_END
