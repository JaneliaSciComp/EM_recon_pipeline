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


def main():
    render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                   owner='cellmap',
                                   project='jrc_zf_cardiac_2')
    stack = "v2_acquire"
    z_layers_to_patch = [12983, 12984, 12985, 12986, 12987, 12988, 12989, 12990, 12991, 12992, 12993, 12994, 12995,
                         13791, 13792, 13793]

    render_request.set_stack_state_to_loading(stack)
    
    for z in z_layers_to_patch:
        resolved_tiles = render_request.get_resolved_tiles_for_layer(stack, z)
        for tile_id in resolved_tiles["tileIdToSpecMap"]:
            tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
            update_source_path_and_labels(tile_spec)
        render_request.save_resolved_tiles(stack, resolved_tiles)

    render_request.set_stack_state_to_complete(stack)


if __name__ == '__main__':
    main()
