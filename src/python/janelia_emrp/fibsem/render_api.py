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
