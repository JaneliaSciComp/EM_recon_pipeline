from dataclasses import dataclass
from typing import Optional, Union, Any

import requests


def submit_get(url: str,
               context: Optional[str] = None) -> Union[dict[str, Any], list[dict[str, Any]], list[str], list[float]]:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting GET {url}{extra_context}")
    response = requests.get(url)
    response.raise_for_status()
    return response.json()


def submit_post(url: str,
                json: Optional[Union[dict[str, Any], list[dict[str, Any]]]],
                context: Optional[str] = None) -> None:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting POST {url}{extra_context}")
    response = requests.post(url, json=json)
    response.raise_for_status()


def submit_put(url: str,
               json: Optional[Union[dict[str, Any], list[dict[str, Any]]]],
               context: Optional[str] = None) -> None:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting PUT {url}{extra_context}")
    response = requests.put(url, json=json)
    response.raise_for_status()


def submit_delete(url: str,
                  context: Optional[str] = None) -> None:
    extra_context = "" if context is None else f" {context}"
    print(f"submitting DELETE {url}{extra_context}")
    response = requests.delete(url)
    response.raise_for_status()


@dataclass
class RenderRequest:
    host: str
    owner: str
    project: str

    def project_url(self) -> str:
        # noinspection HttpUrlsUsage
        return f"http://{self.host}/render-ws/v1/owner/{self.owner}/project/{self.project}"

    def stack_url(self,
                  stack: str) -> str:
        # noinspection HttpUrlsUsage
        return f"{self.project_url()}/stack/{stack}"

    def get_stack_ids(self) -> list[dict[str, Any]]:
        return submit_get(f'{self.project_url()}/stackIds')

    def get_stack_metadata(self,
                           stack: str) -> dict[str, Any]:
        return submit_get(f'{self.stack_url(stack)}')

    def get_z_values(self,
                     stack: str) -> list[float]:
        return submit_get(f'{self.stack_url(stack)}/zValues')

    def get_tile_bounds_for_z(self,
                              stack: str,
                              z: float | int | str) -> list[dict[str, Any]]:
        return submit_get(f'{self.stack_url(stack)}/z/{z}/tileBounds')

    def get_tile_ids_with_pattern(self,
                                  stack: str,
                                  match_pattern: str) -> list[str]:
        return submit_get(f'{self.stack_url(stack)}/tileIds?matchPattern={match_pattern}')

    def get_tile_spec(self,
                      stack: str,
                      tile_id: str) -> dict[str, Any]:
        return submit_get(f'{self.stack_url(stack)}/tile/{tile_id}')

    def get_all_resolved_tiles_for_stack(self,
                                         stack: str,
                                         min_z: Optional[float] = None,
                                         max_z: Optional[float] = None) -> dict[str, Any]:
        query_params = ""
        if min_z is not None:
            query_params += f"?minZ={min_z}"
            if max_z is not None:
                query_params += f"&maxZ={max_z}"
        elif max_z is not None:
            query_params += f"?maxZ={max_z}"
        return submit_get(f'{self.stack_url(stack)}/resolvedTiles{query_params}')

    def get_resolved_tiles_for_z(self,
                                 stack: str,
                                 z: float | int | str) -> dict[str, Any]:
        return submit_get(f'{self.stack_url(stack)}/z/{z}/resolvedTiles')

    def get_resolved_restart_tiles(self,
                                   stack: str) -> dict[str, Any]:
        return submit_get(f'{self.stack_url(stack)}/resolvedTiles?groupId=restart')

    def set_stack_state(self,
                        stack: str,
                        state: str):
        url = f'{self.stack_url(stack)}/state/{state}'
        submit_put(url=url, json=None, context=None)

    def set_stack_state_to_loading(self,
                                   stack: str):
        self.set_stack_state(stack, 'LOADING')

    def set_stack_state_to_complete(self,
                                    stack: str):
        self.set_stack_state(stack, 'COMPLETE')

    def save_resolved_tiles(self,
                            stack: str,
                            resolved_tiles: dict[str, Any],
                            derive_data: bool = False):
        query_params = "?deriveData=true" if derive_data else ""
        url = f'{self.stack_url(stack)}/resolvedTiles{query_params}'
        submit_put(url=url,
                   json=resolved_tiles,
                   context=f'for {len(resolved_tiles["tileIdToSpecMap"])} tile specs')

    def create_stack(self,
                     stack: str,
                     stack_version: dict[str, Any]):
        url = f'{self.stack_url(stack)}'

        submit_post(url=url,
                    json=stack_version)


@dataclass
class MatchRequest:
    host: str
    owner: str
    collection: str

    def owner_url(self) -> str:
        # noinspection HttpUrlsUsage
        return f"http://{self.host}/render-ws/v1/owner/{self.owner}"

    def collection_url(self) -> str:
        # noinspection HttpUrlsUsage
        return f"{self.owner_url()}/matchCollection/{self.collection}"

    def get_all_match_collections_for_owner(self) -> list[dict[str, Any]]:
        return submit_get(f'{self.owner_url()}/matchCollections')

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
                                  group_id: str,
                                  exclude_match_details: bool = False) -> list[dict[str, Any]]:
        query = "?excludeMatchDetails=true" if exclude_match_details else ""
        url = f"{self.collection_url()}/pGroup/{group_id}/matches{query}"
        match_pairs = submit_get(url)
        print(f"retrieved {len(match_pairs)} {self.collection} pairs for groupId {group_id}")

        return match_pairs

    def get_match_pairs_within_group(self,
                                     group_id: str,
                                     exclude_match_details: bool = False) -> list[dict[str, Any]]:
        query = "?excludeMatchDetails=true" if exclude_match_details else ""
        url = f"{self.collection_url()}/group/{group_id}/matchesWithinGroup{query}"
        match_pairs = submit_get(url)
        print(f"retrieved {len(match_pairs)} {self.collection} pairs for groupId {group_id}")

        return match_pairs

    def get_match_pairs_outside_group(self,
                                      group_id: str,
                                      exclude_match_details: bool = False) -> list[dict[str, Any]]:
        query = "?excludeMatchDetails=true" if exclude_match_details else ""
        url = f"{self.collection_url()}/group/{group_id}/matchesOutsideGroup{query}"
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

    def get_match_pair(self,
                       p_group_id: str,
                       p_id: str,
                       q_group_id: str,
                       q_id: str):
        return submit_get(f"{self.collection_url()}/group/{p_group_id}/id/{p_id}/matchesWith/{q_group_id}/id/{q_id}")

    def delete_match_pair(self,
                          p_group_id: str,
                          p_id: str,
                          q_group_id: str,
                          q_id: str):
        submit_delete(f"{self.collection_url()}/group/{p_group_id}/id/{p_id}/matchesWith/{q_group_id}/id/{q_id}")

    def delete_collection(self):
        submit_delete(f"{self.collection_url()}")
