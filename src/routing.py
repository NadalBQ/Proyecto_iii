# src/routing.py

import heapq


def dijkstra(graph, source, target, allowed_edges=None):
    n = len(graph.adj)

    dist = [float("inf")] * n
    prev = [-1] * n

    dist[source] = 0
    pq = [(0, source)]

    while pq:
        d, u = heapq.heappop(pq)

        if d > dist[u]:
            continue

        if u == target:
            break

        for i, edge in enumerate(graph.adj[u]):

            if allowed_edges and not allowed_edges[u][i]:
                continue

            v = edge.to
            nd = d + edge.weight

            if nd < dist[v]:
                dist[v] = nd
                prev[v] = u
                heapq.heappush(pq, (nd, v))

    path = []
    cur = target

    if prev[cur] == -1 and cur != source:
        return None, float("inf")

    while cur != -1:
        path.append(cur)
        cur = prev[cur]

    path.reverse()
    return path, dist[target]