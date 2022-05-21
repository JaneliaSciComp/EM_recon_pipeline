from pathlib import Path

from janelia_emrp.fibsem.h5_to_render import build_tile_spec, build_layers


def test_build_tile_spec():

    layers = build_layers(split_h5_paths=[
        Path("../resources/janelia_emrp/fibsem/small_21-07-31_152727.uint8.h5").resolve()
    ])

    first_layer = layers[0]

    tile_spec = build_tile_spec(h5_path=first_layer.h5_path,
                                dat_path=first_layer.dat_paths[0],
                                z=1,
                                tile_overlap_in_microns=10,
                                tile_attributes=first_layer.retained_headers[0],
                                prior_layer=None,
                                mask_path=None)

    # print(json.dumps(tile_spec, indent=True))

    assert tile_spec["width"] == 100, "invalid width for tile spec"
    assert tile_spec["mipmapLevels"] is not None, "mipmapLevels missing from tile spec"
    assert tile_spec["mipmapLevels"]["0"] is not None, "mipmapLevels 0 missing from tile spec"

    image_url = tile_spec["mipmapLevels"]["0"]["imageUrl"]
    expected_suffix = "small_21-07-31_152727.uint8.h5?dataSet=/0-0-1/mipmap.0&z=0"
    assert image_url is not None, "mipmapLevels 0 imageUrl missing from tile spec"
    assert image_url.endswith(expected_suffix), f"imageUrl '{image_url}' does not end with '{expected_suffix}'"
