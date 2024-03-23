from janelia_emrp.render.web_service_request import MatchRequest


def main():
    host = "em-services-1.int.janelia.org:8080"
    owner = "hess_wafer_53c"
    collection_names = [
        # "s001_m239_match", "s002_m395_match", "s003_m348_match", "s004_m107_match", "s005_m316_match", "s006_m167_match", "s007_m285_match", "s008_m281_match", "s009_m172_match",
        # "s010_m231_match", "s011_m151_match", "s012_m097_match", "s013_m333_match", "s014_m178_match", "s015_m278_match", "s016_m099_match", "s017_m330_match", "s018_m300_match", "s019_m073_match",
        # "s020_m302_match", "s021_m253_match", "s022_m367_match", "s023_m241_match", "s024_m362_match", "s025_m277_match", "s026_m372_match", "s027_m275_match", "s028_m173_match", "s029_m349_match",
        # "s030_m016_match", "s031_m105_match", "s032_m133_match", "s033_m039_match", "s034_m081_match", "s035_m387_match", "s036_m252_match", "s037_m381_match", "s038_m139_match", "s039_m295_match",
        # "s040_m022_match", "s041_m003_match", "s042_m070_match", "s043_m379_match", "s044_m292_match", "s045_m296_match", "s046_m259_match", "s047_m307_match", "s048_m044_match", "s049_m025_match",
        # "s050_m268_match", "s051_m287_match", "s052_m008_match", "s053_m188_match", "s054_m326_match", "s055_m089_match", "s056_m131_match", "s057_m055_match", "s058_m102_match", "s059_m355_match",
        # "s060_m162_match", "s061_m235_match", "s062_m122_match", "s063_m054_match", "s064_m212_match", "s065_m057_match", "s066_m210_match", "s067_m037_match", "s068_m118_match", "s069_m390_match",
        # "s070_m104_match", "s071_m331_match", "s072_m150_match", "s073_m079_match", "s074_m265_match", "s075_m119_match", "s076_m033_match", "s077_m286_match", "s078_m279_match", "s079_m214_match",
        # "s080_m174_match", "s081_m049_match", "s082_m190_match", "s083_m029_match", "s084_m069_match", "s085_m031_match", "s086_m181_match", "s087_m155_match", "s088_m291_match", "s089_m045_match",
        # "s090_m114_match", "s091_m246_match", "s092_m189_match", "s093_m228_match", "s094_m059_match", "s095_m221_match", "s096_m132_match", "s097_m149_match", "s098_m154_match", "s099_m233_match",
        # "s100_m164_match", "s101_m313_match", "s102_m240_match", "s103_m236_match", "s104_m323_match", "s105_m397_match", "s106_m180_match", "s107_m192_match", "s108_m157_match", "s109_m351_match",
        # "s110_m141_match", "s111_m117_match", "s112_m213_match", "s113_m293_match", "s114_m094_match", "s115_m242_match", "s116_m341_match", "s117_m023_match", "s118_m092_match", "s119_m169_match",
        # "s120_m324_match", "s121_m217_match", "s122_m325_match", "s123_m357_match", "s124_m129_match", "s125_m336_match", "s126_m013_match", "s127_m232_match", "s128_m282_match", "s129_m318_match",
        # "s130_m091_match", "s131_m043_match", "s132_m140_match", "s133_m305_match", "s134_m064_match", "s135_m078_match", "s136_m115_match", "s137_m388_match", "s138_m290_match", "s139_m111_match",
        # "s140_m067_match", "s141_m238_match", "s142_m018_match", "s143_m366_match", "s144_m321_match", "s145_m080_match", "s146_m009_match", "s147_m375_match", "s148_m109_match", "s149_m243_match",
        # "s150_m280_match", "s151_m017_match", "s152_m145_match", "s153_m205_match", "s154_m124_match", "s155_m096_match", "s156_m198_match", "s157_m026_match", "s158_m177_match", "s159_m365_match",
        # "s160_m215_match", "s161_m380_match", "s162_m250_match", "s163_m063_match", "s164_m319_match", "s165_m058_match", "s166_m020_match", "s167_m121_match", "s168_m076_match", "s169_m208_match",
        # "s170_m225_match", "s171_m260_match", "s172_m196_match", "s173_m166_match", "s174_m134_match", "s175_m194_match", "s176_m041_match", "s177_m146_match", "s178_m137_match", "s179_m036_match",
        # "s180_m147_match", "s181_m211_match", "s182_m010_match", "s183_m264_match", "s184_m203_match", "s185_m084_match", "s186_m247_match", "s187_m047_match", "s188_m385_match", "s189_m315_match",
        # "s190_m294_match", "s191_m038_match", "s192_m086_match", "s193_m030_match", "s194_m182_match", "s195_m128_match", "s196_m120_match", "s197_m347_match", "s198_m306_match", "s199_m130_match",
        # "s200_m207_match", "s201_m056_match", "s202_m158_match", "s203_m269_match", "s204_m237_match", "s205_m015_match", "s206_m283_match", "s207_m263_match", "s208_m254_match", "s209_m249_match",
        # "s210_m062_match", "s211_m350_match", "s212_m170_match", "s213_m386_match", "s214_m095_match", "s215_m222_match", "s216_m271_match", "s217_m392_match", "s218_m142_match", "s219_m199_match",
        # "s220_m224_match", "s221_m176_match", "s222_m309_match", "s223_m329_match", "s224_m334_match", "s225_m358_match", "s226_m219_match", "s227_m396_match", "s228_m363_match", "s229_m075_match",
        # "s230_m126_match", "s231_m304_match", "s232_m314_match", "s233_m364_match", "s234_m289_match", "s235_m226_match", "s236_m195_match", "s237_m267_match", "s238_m266_match", "s239_m320_match",
        # "s240_m001_match", "s241_m112_match", "s242_m040_match", "s243_m274_match", "s244_m116_match", "s245_m071_match", "s246_m052_match", "s247_m299_match", "s248_m012_match", "s249_m391_match",
        # "s250_m082_match", "s251_m108_match", "s252_m028_match", "s253_m100_match", "s254_m337_match", "s255_m103_match", "s256_m060_match", "s257_m369_match", "s258_m223_match", "s259_m230_match",
        # "s260_m136_match", "s261_m000_match", "s262_m066_match", "s263_m186_match", "s264_m335_match", "s265_m090_match", "s266_m127_match", "s267_m308_match", "s268_m317_match", "s269_m046_match",
        # "s270_m024_match", "s271_m301_match", "s272_m053_match", "s273_m019_match", "s274_m165_match", "s275_m345_match", "s276_m204_match", "s277_m272_match", "s278_m193_match", "s279_m161_match",
        # "s280_m256_match", "s281_m206_match", "s282_m220_match", "s283_m106_match", "s284_m050_match", "s285_m201_match", "s286_m179_match", "s287_m359_match", "s288_m276_match", "s289_m014_match",
        # "s290_m144_match", "s291_m262_match", "s292_m065_match", "s293_m400_match", "s294_m123_match", "s295_m175_match", "s296_m339_match", "s297_m048_match", "s298_m311_match", "s299_m034_match",
        # "s300_m160_match", "s301_m378_match", "s302_m184_match", "s303_m083_match", "s304_m370_match", "s305_m035_match", "s306_m340_match", "s307_m006_match", "s308_m098_match", "s309_m110_match",
        # "s310_m368_match", "s311_m297_match", "s312_m171_match", "s313_m298_match", "s314_m338_match", "s315_m303_match", "s316_m068_match", "s317_m361_match", "s318_m389_match", "s319_m002_match",
        # "s320_m021_match", "s321_m101_match", "s322_m005_match", "s323_m354_match", "s324_m156_match", "s325_m245_match", "s326_m200_match", "s327_m244_match", "s328_m135_match", "s329_m401_match",
        # "s330_m085_match", "s331_m251_match", "s332_m027_match", "s333_m163_match", "s334_m343_match", "s335_m011_match", "s336_m373_match", "s337_m394_match", "s338_m332_match", "s339_m032_match",
        # "s340_m371_match", "s341_m356_match", "s342_m191_match", "s343_m261_match", "s344_m216_match", "s345_m327_match", "s346_m312_match", "s347_m342_match", "s348_m061_match", "s349_m288_match",
        # "s350_m352_match", "s351_m218_match", "s352_m234_match", "s353_m042_match", "s354_m093_match", "s355_m310_match", "s356_m197_match", "s357_m051_match", "s358_m074_match", "s359_m248_match",
        # "s360_m346_match", "s361_m125_match", "s362_m255_match", "s363_m344_match", "s364_m374_match", "s365_m383_match", "s366_m088_match", "s367_m007_match", "s368_m257_match", "s369_m143_match",
        # "s370_m159_match", "s371_m087_match", "s372_m402_match", "s373_m258_match", "s374_m077_match", "s375_m284_match", "s376_m398_match", "s377_m202_match", "s378_m376_match", "s379_m229_match",
        # "s380_m382_match", "s381_m377_match", "s382_m328_match", "s383_m004_match", "s384_m384_match", "s385_m227_match", "s386_m270_match", "s387_m187_match", "s388_m072_match", "s389_m322_match",
        # "s390_m273_match", "s391_m393_match", "s392_m168_match", "s393_m138_match", "s394_m360_match", "s395_m113_match", "s396_m153_match", "s397_m148_match", "s398_m183_match", "s399_m185_match",
        # "s400_m152_match", "s401_m353_match", "s402_m399_match"
    ]
    pair_type_to_delete = "outside"  # "within" or "outside"

    # normal weight: 1.0
    # "sameLayerDerivedMatchWeight": 0.15
    # "crossLayerDerivedMatchWeight": 0.1
    # "secondPassDerivedMatchWeight": 0.05
    min_match_weight_to_keep = -9.9  # to remove match data, change this to 1.1 or 0.2 or 0.13 or 0.08

    for collection_name in collection_names:
        
        match_request = MatchRequest(host=host,
                                     owner=owner,
                                     collection=collection_name)

        group_ids = sorted(match_request.get_p_group_ids(), key=float)

        for group_id in group_ids:

            if pair_type_to_delete == "within":
                match_pairs = match_request.get_match_pairs_within_group(group_id=group_id)
            elif pair_type_to_delete == "outside":
                match_pairs = match_request.get_match_pairs_outside_group(group_id=group_id)
            else:
                raise ValueError(f"invalid pair type: {pair_type_to_delete}")

            deleted_count = 0
            for pair in match_pairs:
                if pair["matches"]["w"][0] < min_match_weight_to_keep:
                    match_request.delete_match_pair(p_group_id=pair["pGroupId"],
                                                    p_id=pair["pId"],
                                                    q_group_id=pair["qGroupId"],
                                                    q_id=pair["qId"])
                    deleted_count += 1

            print(f"deleted {deleted_count} pairs {pair_type_to_delete} group {group_id}")

    print("Done!")


if __name__ == '__main__':
    main()
