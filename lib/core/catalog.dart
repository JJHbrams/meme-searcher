import 'models.dart';

class MemeFamily {
  const MemeFamily({
    required this.id,
    required this.name,
    required this.aliases,
    this.similarAliases = const [],
  });

  final String id;
  final String name;
  final List<String> aliases;
  final List<String> similarAliases;
}

class CatalogTag {
  const CatalogTag({
    required this.id,
    required this.label,
    required this.aliases,
  });

  final String id;
  final String label;
  final List<String> aliases;
}

class MemeCatalog {
  const MemeCatalog({required this.families, required this.tags});

  final List<MemeFamily> families;
  final Map<String, CatalogTag> tags;

  static const bundled = MemeCatalog(
    families: [
      MemeFamily(
        id: 'approved',
        name: '너클즈 승인',
        aliases: ['approved', '승인', '너클즈', 'knuckles'],
      ),
      MemeFamily(
        id: 'coming',
        name: '좋다 지금 간다 기다려라',
        aliases: ['좋다 지금 간다 기다려라', '케장콘', '케쟝콘'],
        similarAliases: ['내가 간다 기다려라', '당장 간다 기다려라'],
      ),
      MemeFamily(
        id: 'mold-breaker',
        name: '틀깨기!',
        aliases: ['틀깨기', '틀 깨기', 'mold breaker'],
      ),
    ],
    tags: {
      'helldivers': CatalogTag(
        id: 'helldivers',
        label: '헬다이버즈',
        aliases: ['헬다2', '헬다이버즈'],
      ),
      'kejang': CatalogTag(
        id: 'kejang',
        label: '케장콘',
        aliases: ['케장', '케쟝', '케장콘'],
      ),
      'knuckles': CatalogTag(
        id: 'knuckles',
        label: '너클즈',
        aliases: ['너클즈', 'knuckles'],
      ),
      'sonic': CatalogTag(id: 'sonic', label: '소닉', aliases: ['소닉', 'sonic']),
      'arona': CatalogTag(id: 'arona', label: '아로나', aliases: ['아로나', 'arona']),
    },
  );

  static const seedAssets = [
    SeedAsset(
      id: 'knuckles-approved',
      title: '너클즈 APPROVED',
      familyId: 'approved',
      familyName: '너클즈 승인',
      variant: '너클즈 도장',
      tagIds: ['knuckles', 'sonic'],
      file: 'assets/seed-assets/approved-knuckles-tenor.gif',
      sourceUrl: 'https://tenor.com/view/knuckles-knuckles-the-echidna-approved-knuckles-approved-knuckles-approve-gif-7865806417645174166',
    ),
    SeedAsset(
      id: 'knuckles-approved-alt',
      title: '너클즈 APPROVED (KYM)',
      familyId: 'approved',
      familyName: '너클즈 승인',
      variant: '긴 버전',
      tagIds: ['knuckles', 'sonic'],
      file: 'assets/seed-assets/approved-knuckles-kym.gif',
      sourceUrl:
          'https://knowyourmeme.com/photos/2907981-meme-approved-by-knuckles',
    ),
    SeedAsset(
      id: 'kejang-coming',
      title: '좋다 지금 간다 기다려라',
      familyId: 'coming',
      familyName: '좋다 지금 간다 기다려라',
      variant: '케장콘',
      tagIds: ['kejang'],
      file: 'assets/seed-assets/kejang-coming-ruliweb.png',
      sourceUrl: 'https://m.ruliweb.com/community/board/300779/read/44957908',
    ),
    SeedAsset(
      id: 'helldivers-coming',
      title: '좋다 지금 간다 기다려라',
      familyId: 'coming',
      familyName: '좋다 지금 간다 기다려라',
      variant: '헬다이버즈 2',
      tagIds: ['helldivers'],
      file: 'assets/seed-assets/helldivers-coming-arca.png',
      sourceUrl: 'https://arca.live/b/helldivers2/187859047?p=1',
    ),
    SeedAsset(
      id: 'arona-mold-breaker',
      title: '아로나의 틀깨기!',
      familyId: 'mold-breaker',
      familyName: '틀깨기!',
      variant: '아로나',
      tagIds: ['arona'],
      file: 'assets/seed-assets/arona-mold-breaker-x.webp',
      sourceUrl: 'https://x.com/teska1567/status/1763800216296370399',
    ),
  ];

  MemeAsset seedToAsset(SeedAsset seed) {
    final family = families.firstWhere((value) => value.id == seed.familyId);
    return MemeAsset(
      id: seed.id,
      title: seed.title,
      origin: 'seed',
      familyId: seed.familyId,
      familyName: seed.familyName,
      variant: seed.variant,
      bundledAssetPath: seed.file,
      sourceUrl: seed.sourceUrl,
      format: seed.file.endsWith('.gif')
          ? 'GIF'
          : seed.file.endsWith('.webp')
          ? 'WEBP'
          : 'PNG',
      animated: seed.file.endsWith('.gif'),
      tags: seed.tagIds
          .map((id) => MemeTag(id: id, label: tags[id]!.label))
          .toList(),
      aliases: family.aliases,
      verified: true,
    );
  }
}

class SeedAsset {
  const SeedAsset({
    required this.id,
    required this.title,
    required this.familyId,
    required this.familyName,
    required this.variant,
    required this.tagIds,
    required this.file,
    required this.sourceUrl,
  });

  final String id;
  final String title;
  final String familyId;
  final String familyName;
  final String variant;
  final List<String> tagIds;
  final String file;
  final String sourceUrl;
}
