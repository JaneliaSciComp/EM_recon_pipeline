from dataclasses import dataclass
from typing import Optional, Union, Any

import requests


def submit_get(url: str,
               context: Optional[str] = None) -> Union[dict[str, Any], list[dict[str, Any]], list[str]]:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting GET {url}{extra_context}")
    get_response = requests.get(url)
    get_response.raise_for_status()
    return get_response.json()


def submit_put(url: str,
               json: Optional[Union[dict[str, Any], list[dict[str, Any]]]],
               context: Optional[str] = None) -> None:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting PUT {url}{extra_context}")
    put_response = requests.put(url, json=json)
    put_response.raise_for_status()


@dataclass
class RenderRequest:
    host: str
    owner: str
    project: str

    def stack_url(self, stack) -> str:
        # noinspection HttpUrlsUsage
        return f"http://{self.host}/render-ws/v1/owner/{self.owner}/project/{self.project}/stack/{stack}"

    def get_tile_spec(self, stack, tile_id) -> dict[str, Any]:
        return submit_get(f'{self.stack_url(stack)}/tile/{tile_id}')

    def get_resolved_tiles_for_layer(self, stack, z):
        return submit_get(f'{self.stack_url(stack)}/z/{z}/resolvedTiles')

    def set_stack_state(self, stack, state):
        url = f'{self.stack_url(stack)}/state/{state}'
        submit_put(url=url, json=None, context=None)

    def set_stack_state_to_loading(self, stack):
        self.set_stack_state(stack, 'LOADING')

    def set_stack_state_to_complete(self, stack):
        self.set_stack_state(stack, 'COMPLETE')

    def save_resolved_tiles(self, stack, resolved_tiles):
        url = f'{self.stack_url(stack)}/resolvedTiles'
        submit_put(url=url,
                   json=resolved_tiles,
                   context=f'for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')


@dataclass
class MatchRequest:
    host: str
    owner: str
    collection: str

    def collection_url(self) -> str:
        # noinspection HttpUrlsUsage
        return f"http://{self.host}/render-ws/v1/owner/{self.owner}/matchCollection/{self.collection}"

    def p_group_ids_url(self) -> str:
        return f"{self.collection_url()}/pGroupIds"

    def get_p_group_ids(self) -> list[str]:
        p_group_ids = submit_get(self.p_group_ids_url())
        print(f"retrieved {len(p_group_ids)} pGroupId values for the {self.collection} collection")

        return p_group_ids

    def match_pairs_for_group_url(self,
                                  group_id: str) -> str:
        return f"{self.collection_url()}/pGroup/{group_id}/matches"

    def get_match_pairs_for_group(self,
                                  group_id: str) -> list[dict[str, Any]]:
        match_pairs = submit_get(self.match_pairs_for_group_url(group_id))
        print(f"retrieved {len(match_pairs)} {self.collection} pairs for groupId {group_id}")

        return match_pairs

    def save_match_pairs(self,
                         group_id: str,
                         match_pairs: list[dict[str, Any]]):
        if len(match_pairs) > 0:
            matches_url = f"{self.collection_url()}/matches"
            submit_put(url=matches_url,
                       json=match_pairs,
                       context=f"for {len(match_pairs)} pairs with groupId {group_id}")
