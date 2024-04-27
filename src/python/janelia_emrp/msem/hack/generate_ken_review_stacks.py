#!/usr/bin/env python

from janelia_emrp.render.web_service_request import RenderRequest


def main():
    target_stack_prefix_to_z_index = {
        "scan_020": 19,
        "scan_last": -1
    }
    target_stack_version = {
        "stackResolutionX": 8, "stackResolutionY": 8, "stackResolutionZ": 8,
        "mipmapPathBuilder": {
            "rootPath": "/nrs/hess/data/hess_wafer_53/mipmaps/",
            "numberOfLevels": 3,
            "extension": "tif"
        }
    }

    target_render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                          owner='hess_wafer_53d',
                                          project='ken_review')

    slab_groups = {
        "s001_to_099": [
            "slab_000_to_009", "slab_010_to_019", "slab_020_to_029", "slab_030_to_039", "slab_040_to_049",
            "slab_050_to_059", "slab_060_to_069", "slab_070_to_079", "slab_080_to_089", "slab_090_to_099"
        ],
        "s100_to_199": [
            "slab_100_to_109", "slab_110_to_119", "slab_120_to_129", "slab_130_to_139", "slab_140_to_149",
            "slab_150_to_159", "slab_160_to_169", "slab_170_to_179", "slab_180_to_189", "slab_190_to_199"
        ],
        "s200_to_249": [
            "slab_200_to_209", "slab_210_to_219", "slab_220_to_229", "slab_230_to_239", "slab_240_to_249",
            "slab_250_to_259", "slab_260_to_269", "slab_270_to_279", "slab_280_to_289", "slab_290_to_299"
        ],
        "s300_to_402": [
            "slab_300_to_309", "slab_310_to_319", "slab_320_to_329", "slab_330_to_339", "slab_340_to_349",
            "slab_350_to_359", "slab_360_to_369", "slab_370_to_379", "slab_380_to_389", "slab_390_to_399",
            "slab_400_to_402"
        ]
    }

    target_z = 1
    for slab_group_name in sorted(slab_groups.keys()):

        sorted_prefixes = sorted(target_stack_prefix_to_z_index.keys())

        for target_stack_prefix in sorted_prefixes:
            target_stack_name = f"{target_stack_prefix}_{slab_group_name}"
            target_render_request.create_stack(stack=target_stack_name,
                                               stack_version=target_stack_version)

        for project in slab_groups[slab_group_name]:
            render_request = RenderRequest(host='em-services-1.int.janelia.org:8080',
                                           owner='hess_wafer_53d',
                                           project=project)

            project_stack_names = sorted([stack_id["stack"] for stack_id in render_request.get_stack_ids()])

            for stack_name in project_stack_names:

                # only include acquisition stacks and skip s000_m209
                if len(stack_name) > 9 or stack_name == "s000_m209":
                    continue

                z_values = list(map(int, render_request.get_z_values(stack_name)))

                for target_stack_prefix in sorted_prefixes:
                    target_stack_name = f"{target_stack_prefix}_{slab_group_name}"
                    z_index = target_stack_prefix_to_z_index[target_stack_prefix]
                    z = z_values[z_index]
                    resolved_tiles = render_request.get_resolved_tiles_for_z(stack_name, z)
                    for tile_id in resolved_tiles["tileIdToSpecMap"]:
                        tile_spec = resolved_tiles["tileIdToSpecMap"][tile_id]
                        tile_spec["z"] = target_z
                    target_render_request.save_resolved_tiles(target_stack_name, resolved_tiles)

                target_z += 1

        for target_stack_prefix in sorted_prefixes:
            target_stack_name = f"{target_stack_prefix}_{slab_group_name}"
            target_render_request.set_stack_state_to_complete(target_stack_name)


if __name__ == '__main__':
    main()
