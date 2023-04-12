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

    def get_p_group_ids(self) -> list[str]:
        url = f"{self.collection_url()}/pGroupIds"
        p_group_ids = submit_get(url)
        print(f"retrieved {len(p_group_ids)} pGroupId values for the {self.collection} collection")

        return p_group_ids

    # [
    #   {
    #     "pGroupId": "1.0",
    #     "pId": "23-01-24_000020_0-0-0.1.0",
    #     "qGroupId": "1.0",
    #     "qId": "23-01-24_000020_0-0-1.1.0",
    #     "matchCount": 36
    #   }, ...
    # ]
    def get_pairs_with_match_counts_for_group(self,
                                              group_id: str) -> list[dict[str, Any]]:
        url = f"{self.collection_url()}/pGroup/{group_id}/matchCounts"
        match_counts = submit_get(url)
        print(f"retrieved {len(match_counts)} {self.collection} pairs for groupId {group_id}")
        return match_counts

    def get_match_pairs_for_group(self,
                                  group_id: str) -> list[dict[str, Any]]:
        url = f"{self.collection_url()}/pGroup/{group_id}/matches"
        match_pairs = submit_get(url)
        print(f"retrieved {len(match_pairs)} {self.collection} pairs for groupId {group_id}")

        return match_pairs

    def save_match_pairs(self,
                         group_id: str,
                         match_pairs: list[dict[str, Any]]):
        if len(match_pairs) > 0:
            url = f"{self.collection_url()}/matches"
            submit_put(url=url,
                       json=match_pairs,
                       context=f"for {len(match_pairs)} pairs with groupId {group_id}")
