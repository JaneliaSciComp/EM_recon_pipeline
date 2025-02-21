from janelia_emrp.msem.tile_id import TileID


def test_tile_id():
    wafer_id = "60"
    scan = 51
    slab = 160
    mfov = 10
    sfov = 12

    tile_id_a : TileID = TileID(wafer_id=wafer_id, slab=slab, scan=scan, mfov=mfov, sfov=sfov)
    assert tile_id_a.__str__() == "w60_magc0160_scan051_m0010_r34_s13", "invalid tile_id"

    tile_id_b : TileID = TileID(wafer_id, slab, scan, mfov, sfov)
    assert tile_id_a == tile_id_b, "different ids constructed for what should be the same tile"
