#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def update_source_path_and_labels(tile_spec):
    labels = {"patch"}
    if "labels" in tile_spec.keys():
        labels.update(tile_spec["labels"])

    # change /nrs/cellmap/data/jrc_zf-cardiac-2/align/Merlin-6257/...uint8.h5?dataSet=/0-0-0/mipmap.0&z=0
    # to     /nrs/cellmap/data/jrc_zf-cardiac-2/fix/align-c1/Merlin-6257/...uint8.h5?dataSet=/0-0-0/mipmap.0&z=0
    image_url = tile_spec["mipmapLevels"]["0"]["imageUrl"]
    tile_spec["mipmapLevels"]["0"]["imageUrl"] = image_url.replace('/jrc_zf-cardiac-2/align/',
                                                                   '/jrc_zf-cardiac-2/fix/align-c1/')
    tile_spec["labels"] = sorted(labels)


def update_thymus_source_path(tile_spec,
                              base_path):
    # /nrs/cellmap/data/jrc_mus-thymus-1 ...
    #   change .../align/Merlin-6282/2023/06/05/19/Merlin-6282_23-06-05_190627.uint8.h5?dataSet=/0-0-1/mipmap.0&z=0
    #   to     .../tiles/jrc_mus_thymus_1/v2_acquire_align/20231129_180000/001/2/1240/23-06-05_190627_0-0-0.1240.0.tif
    mipmap_zero = tile_spec["mipmapLevels"]["0"]
    tile_id = tile_spec["tileId"]
    z_int = int(tile_spec["z"])
    thousands = int(z_int / 1000)
    hundreds = int((z_int % 1000) / 100)

    mipmap_zero["imageUrl"] = f"{base_path}/{thousands:03}/{hundreds}/{z_int}/{tile_id}.tif"
    mipmap_zero["imageLoaderType"] = "IMAGEJ_DEFAULT"


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='cellmap',
                                   project='jrc_mus_thymus_1')
    stack = "v2_acquire_align_bgic_gauss"
    base_path = "file:///nrs/cellmap/data/jrc_mus-thymus-1/tiles/jrc_mus_thymus_1/v2_acquire_align/20231130_160900"

    # TODO: delete mipmap builder from stack metadata after replacing h5s with bg corrected tiffs

    z_layers_to_patch = render_request.get_z_values(stack)
    # z_layers_to_patch = [ 3297.0, 10230.0, 12914.0 ]

    render_request.set_stack_state_to_loading(stack)
    
    for z in z_layers_to_patch:
        resolved_tiles = render_request.get_resolved_tiles_for_z(stack, z)
        for tile_id in resolved_tiles["tileIdToSpecMap"]:
            tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
            update_thymus_source_path(tile_spec, base_path)
        render_request.save_resolved_tiles(stack, resolved_tiles)

    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
