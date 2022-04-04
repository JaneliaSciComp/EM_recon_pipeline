from typing import List, Dict, Any

import requests

from janelia_emrp.fibsem.volume_transfer_info import RenderConnect


def get_response_json(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("request failed for %s\n  status_code: %d\n  text: %s" %
                        (url, response.status_code, response.text))
    return response.json()


class RenderApi:
    def __init__(self,
                 render_owner: str,
                 render_project: str,
                 render_connect: RenderConnect):
        self.render_owner = render_owner
        self.render_project = render_project
        self.render_connect = render_connect

    def get_ws_url(self):
        # noinspection HttpUrlsUsage
        return f"http://{self.render_connect.host}:{self.render_connect.port}/render-ws/v1"

    def get_project_url(self):
        return f"{self.get_ws_url()}/owner/{self.render_owner}/project/{self.render_project}"

    def get_stack_url(self,
                      stack: str):
        return f"{self.get_project_url()}/stack/{stack}"

    def save_resolved_tiles(self,
                            stack: str,
                            resolved_tiles: Dict[str, Any]):
        url = f"{self.get_stack_url(stack)}/resolvedTiles"
        print(f'submitting PUT {url} for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')

        response = requests.put(url, json=resolved_tiles)
        response.raise_for_status()

    def save_tile_specs(self,
                        stack: str,
                        tile_specs: List[Dict[str, Any]]):
        tile_id_to_spec_map = {}
        for tile_spec in tile_specs:
            tile_id_to_spec_map[tile_spec["tileId"]] = tile_spec

        resolved_tiles = {"tileIdToSpecMap": tile_id_to_spec_map}

        self.save_resolved_tiles(stack=stack,
                                 resolved_tiles=resolved_tiles)

    def save_mipmap_path_builder(self,
                                 stack: str,
                                 mipmap_path_builder: Dict[str, Any]):
        url = f"{self.get_stack_url(stack)}/mipmapPathBuilder"
        print(f'submitting PUT {url}')

        response = requests.put(url, json=mipmap_path_builder)
        response.raise_for_status()


if __name__ == "__main__":

    render_api = RenderApi(render_owner="test_h5",
                           render_project="BR_Sec07",
                           render_connect=RenderConnect(host="10.40.3.162",
                                                        port=8080,
                                                        web_only=True,
                                                        validate_client=False,
                                                        client_scripts="/groups/flyTEM/flyTEM/render/bin",
                                                        memGB="1G"))

    tile_specs = [
        {
            "tileId": "21-06-30_120015_0-0-0.1.0",
            "layout": {
                "sectionId": "1.0",
                "imageRow": 0,
                "imageCol": 0,
                "stageX": -6250,
                "stageY": -1750
            },
            "z": 1,
            "minX": -6250,
            "minY": -1750,
            "maxX": 125,
            "maxY": 1750,
            "width": 6375,
            "height": 3500,
            "minIntensity": 0,
            "maxIntensity": 255,
            "mipmapLevels": {
                "0": {
                    "imageUrl": "file:///nrs/flyem/render/h5/align/Z0720-07m_BR_Sec07/Merlin-4238/2021/06/30/12/Merlin-4238_21-06-30_120015.uint8.h5?dataSet=0-0-0.mipmap.0&z=0",
                    "imageLoaderType": "H5_SLICE",
                    "maskUrl": "file:/groups/flyem/data/render/pre_iso/masks/mask_6375x3500_left_100.tif"
                }
            },
            "transforms": {
                "type": "list",
                "specList": [
                    {
                        "type": "leaf",
                        "className": "mpicbg.trakem2.transform.AffineModel2D",
                        "dataString": "1.0000000000 0.0000000000 0.0000000000 1.0000000000 -6250.0000000000 -1750.0000000000"
                    }
                ]
            },
            "meshCellSize": 64
        },
        {
            "tileId": "21-06-30_120015_0-0-1.1.0",
            "layout": {
                "sectionId": "1.0",
                "imageRow": 0,
                "imageCol": 1,
                "stageX": -126,
                "stageY": -1750
            },
            "z": 1,
            "minX": -126,
            "minY": -1750,
            "maxX": 6249,
            "maxY": 1750,
            "width": 6375,
            "height": 3500,
            "minIntensity": 0,
            "maxIntensity": 255,
            "mipmapLevels": {
                "0": {
                    "imageUrl": "file:///nrs/flyem/render/h5/align/Z0720-07m_BR_Sec07/Merlin-4238/2021/06/30/12/Merlin-4238_21-06-30_120015.uint8.h5?dataSet=0-0-1.mipmap.0&z=0",
                    "imageLoaderType": "H5_SLICE",
                    "maskUrl": "file:/groups/flyem/data/render/pre_iso/masks/mask_6375x3500_left_100.tif"
                }
            },
            "transforms": {
                "type": "list",
                "specList": [
                    {
                        "type": "leaf",
                        "className": "mpicbg.trakem2.transform.AffineModel2D",
                        "dataString": "1.0000000000 0.0000000000 0.0000000000 1.0000000000 -126.0000000000 -1750.0000000000"
                    }
                ]
            },
            "meshCellSize": 64
        },
        {
            "tileId": "21-06-30_120056_0-0-1.2.0",
            "layout": {
                "sectionId": "2.0",
                "imageRow": 0,
                "imageCol": 1,
                "stageX": -126,
                "stageY": -1750,
                "distanceZ": 8.106231689453125
            },
            "z": 2,
            "minX": -126,
            "minY": -1750,
            "maxX": 6249,
            "maxY": 1750,
            "width": 6375,
            "height": 3500,
            "minIntensity": 0,
            "maxIntensity": 255,
            "mipmapLevels": {
                "0": {
                    "imageUrl": "file:///nrs/flyem/render/h5/align/Z0720-07m_BR_Sec07/Merlin-4238/2021/06/30/12/Merlin-4238_21-06-30_120056.uint8.h5?dataSet=0-0-1.mipmap.0&z=0",
                    "imageLoaderType": "H5_SLICE",
                    "maskUrl": "file:/groups/flyem/data/render/pre_iso/masks/mask_6375x3500_left_100.tif"
                }
            },
            "transforms": {
                "type": "list",
                "specList": [
                    {
                        "type": "leaf",
                        "className": "mpicbg.trakem2.transform.AffineModel2D",
                        "dataString": "1.0000000000 0.0000000000 0.0000000000 1.0000000000 -126.0000000000 -1750.0000000000"
                    }
                ]
            }
        },
        {
            "tileId": "21-06-30_120056_0-0-0.2.0",
            "layout": {
                "sectionId": "2.0",
                "imageRow": 0,
                "imageCol": 0,
                "stageX": -6250,
                "stageY": -1750
            },
            "z": 2,
            "minX": -6250,
            "minY": -1750,
            "maxX": 125,
            "maxY": 1750,
            "width": 6375,
            "height": 3500,
            "minIntensity": 0,
            "maxIntensity": 255,
            "mipmapLevels": {
                "0": {
                    "imageUrl": "file:///nrs/flyem/render/h5/align/Z0720-07m_BR_Sec07/Merlin-4238/2021/06/30/12/Merlin-4238_21-06-30_120056.uint8.h5?dataSet=0-0-0.mipmap.0&z=0",
                    "imageLoaderType": "H5_SLICE",
                    "maskUrl": "file:/groups/flyem/data/render/pre_iso/masks/mask_6375x3500_left_100.tif"
                }
            },
            "transforms": {
                "type": "list",
                "specList": [
                    {
                        "type": "leaf",
                        "className": "mpicbg.trakem2.transform.AffineModel2D",
                        "dataString": "1.0000000000 0.0000000000 0.0000000000 1.0000000000 -6250.0000000000 -1750.0000000000"
                    }
                ]
            },
            "meshCellSize": 64
        }
    ]

    render_api.save_tile_specs(stack="v1_acquire",
                               tile_specs=tile_specs[1:3])