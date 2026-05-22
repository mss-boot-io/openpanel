import { Setting } from '@/api/interface/setting';
import { listNodeOptions, listOpenNodeOptions, loadNodeByUser } from '@/api/modules/setting';
import { GlobalStore } from '@/store';

export const changeToLocal = async () => {
    const globalStore = GlobalStore();
    let nodes = await listNodes('all');
    if (nodes.length === 0) {
        setDefaultNodeInfo();
        return;
    }
    if (globalStore.isAdmin) {
        for (const item of nodes) {
            if (item.name === 'local') {
                globalStore.currentNode = item.value || 'local';
                globalStore.currentNodeAddr = item.addr;
                return;
            }
        }
    }
    globalStore.currentNode = nodes[0].value || nodes[0].name;
    globalStore.currentNodeAddr = nodes[0].addr;
};

export async function listNodes(type: string): Promise<Array<Setting.NodeItem>> {
    const globalStore = GlobalStore();
    const mergeOpenNodes = async (nodes: Array<Setting.NodeItem>) => {
        if (!globalStore.isAdmin) {
            return nodes;
        }
        try {
            const res = await listOpenNodeOptions();
            const hasLocal = nodes.some((item) => item.name === 'local' || item.value === 'local');
            const openNodes = (res.data || []).filter((item) => hasLocal ? item.name !== 'local' : true);
            return [...nodes, ...openNodes];
        } catch (error) {
            return nodes;
        }
    };
    try {
        if (globalStore.isAdmin) {
            const res = await listNodeOptions(type);
            return await mergeOpenNodes(res.data || []);
        } else {
            const res = await loadNodeByUser();
            return res.data || [];
        }
    } catch (error) {
        return await mergeOpenNodes([]);
    }
}

export const setDefaultNodeInfo = () => {
    const globalStore = GlobalStore();
    globalStore.currentNode = 'local';
    globalStore.currentNodeAddr = '127.0.0.1';
};
