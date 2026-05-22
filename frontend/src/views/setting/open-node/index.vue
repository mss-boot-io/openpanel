<template>
    <div v-loading="loading">
        <LayoutContent title="Open Nodes">
            <template #leftToolBar>
                <el-button type="primary" icon="Plus" @click="onOpenDialog()">
                    {{ $t('commons.button.add') }}
                </el-button>
            </template>
            <template #rightToolBar>
                <TableSearch @search="search()" v-model:searchName="paginationConfig.info" />
                <TableRefresh @search="search()" />
            </template>
            <template #main>
                <ComplexTable :pagination-config="paginationConfig" @search="search" :data="data">
                    <el-table-column
                        :label="$t('commons.table.name')"
                        :min-width="120"
                        prop="name"
                        show-overflow-tooltip
                    />
                    <el-table-column label="Base URL" :min-width="180" prop="baseUrl" show-overflow-tooltip />
                    <el-table-column :label="$t('commons.table.status')" :min-width="100" prop="status">
                        <template #default="{ row }">
                            <el-tag :type="row.status === 'Success' ? 'success' : 'danger'">
                                {{ row.status || '-' }}
                            </el-tag>
                        </template>
                    </el-table-column>
                    <el-table-column
                        :label="$t('commons.table.updatedAt')"
                        :min-width="150"
                        prop="lastCheckAt"
                        show-overflow-tooltip
                    >
                        <template #default="{ row }">
                            {{ row.lastCheckAt ? dateFormat(0, 0, row.lastCheckAt) : '-' }}
                        </template>
                    </el-table-column>
                    <el-table-column
                        :label="$t('commons.table.description')"
                        :min-width="120"
                        prop="description"
                        show-overflow-tooltip
                    />
                    <el-table-column
                        :label="$t('commons.table.message')"
                        :min-width="160"
                        prop="message"
                        show-overflow-tooltip
                    />
                    <fu-table-operations
                        width="260px"
                        :buttons="buttons"
                        :ellipsis="10"
                        :label="$t('commons.table.operate')"
                        fix
                    />
                </ComplexTable>
            </template>
        </LayoutContent>

        <el-dialog v-model="dialogVisible" :title="dialogTitle" width="560px" destroy-on-close>
            <el-form ref="formRef" :model="form" :rules="rules" label-width="130px">
                <el-form-item :label="$t('commons.table.name')" prop="name">
                    <el-input v-model.trim="form.name" maxlength="128" />
                </el-form-item>
                <el-form-item label="Base URL" prop="baseUrl">
                    <el-input v-model.trim="form.baseUrl" placeholder="https://example.com:9999" />
                </el-form-item>
                <el-form-item label="API Key" prop="apiKey">
                    <el-input v-model.trim="form.apiKey" type="password" show-password />
                </el-form-item>
                <el-form-item label="Skip TLS Verify">
                    <el-switch v-model="form.skipTLSVerify" />
                </el-form-item>
                <el-form-item :label="$t('commons.table.description')">
                    <el-input v-model="form.description" type="textarea" :rows="3" maxlength="256" />
                </el-form-item>
            </el-form>
            <template #footer>
                <el-button @click="dialogVisible = false">{{ $t('commons.button.cancel') }}</el-button>
                <el-button :loading="testLoading" @click="onTest">
                    {{ $t('commons.button.verify') }}
                </el-button>
                <el-button type="primary" :loading="submitLoading" @click="onSubmit">
                    {{ $t('commons.button.confirm') }}
                </el-button>
            </template>
        </el-dialog>
    </div>
</template>

<script lang="ts" setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { ElForm, ElMessageBox } from 'element-plus';
import type { FormRules } from 'element-plus';
import {
    createOpenNode,
    deleteOpenNode,
    searchOpenNodes,
    testOpenNode,
    updateOpenNode,
} from '@/api/modules/setting';
import { Setting } from '@/api/interface/setting';
import { dateFormat } from '@/utils/date';
import { MsgSuccess } from '@/utils/message';
import i18n from '@/lang';

const loading = ref(false);
const submitLoading = ref(false);
const testLoading = ref(false);
const dialogVisible = ref(false);
const formRef = ref<InstanceType<typeof ElForm>>();
const data = ref<Array<Setting.OpenNodeItem>>([]);

const paginationConfig = reactive({
    cacheSizeKey: 'open-node-size',
    currentPage: 1,
    pageSize: Number(localStorage.getItem('open-node-size')) || 20,
    total: 0,
    info: '',
});

const form = reactive<Setting.OpenNodeOperate>({
    id: 0,
    name: '',
    baseUrl: '',
    apiKey: '',
    skipTLSVerify: false,
    description: '',
});

const isEdit = computed(() => !!form.id);
const dialogTitle = computed(() => (isEdit.value ? i18n.global.t('commons.button.edit') : i18n.global.t('commons.button.add')));

const rules = reactive<FormRules>({
    name: [{ required: true, message: i18n.global.t('commons.rule.requiredInput'), trigger: 'blur' }],
    baseUrl: [{ required: true, message: i18n.global.t('commons.rule.requiredInput'), trigger: 'blur' }],
    apiKey: [
        {
            validator: (_rule, value, callback) => {
                if (!isEdit.value && !value) {
                    callback(new Error(i18n.global.t('commons.rule.requiredInput')));
                    return;
                }
                callback();
            },
            trigger: 'blur',
        },
    ],
});

const search = async () => {
    loading.value = true;
    try {
        const res = await searchOpenNodes({
            page: paginationConfig.currentPage,
            pageSize: paginationConfig.pageSize,
            info: paginationConfig.info,
        });
        data.value = res.data.items || [];
        paginationConfig.total = res.data.total;
    } finally {
        loading.value = false;
    }
};

const resetForm = () => {
    form.id = 0;
    form.name = '';
    form.baseUrl = '';
    form.apiKey = '';
    form.skipTLSVerify = false;
    form.description = '';
};

const onOpenDialog = (row?: Setting.OpenNodeItem) => {
    resetForm();
    if (row) {
        form.id = row.id;
        form.name = row.name;
        form.baseUrl = row.baseUrl;
        form.skipTLSVerify = row.skipTLSVerify;
        form.description = row.description || '';
    }
    dialogVisible.value = true;
};

const onSubmit = async () => {
    if (!formRef.value) {
        return;
    }
    await formRef.value.validate();
    submitLoading.value = true;
    try {
        if (isEdit.value) {
            await updateOpenNode(form);
        } else {
            await createOpenNode(form);
        }
        MsgSuccess(i18n.global.t('commons.msg.operationSuccess'));
        dialogVisible.value = false;
        search();
    } finally {
        submitLoading.value = false;
    }
};

const onTest = async () => {
    if (!formRef.value) {
        return;
    }
    await formRef.value.validate();
    testLoading.value = true;
    try {
        await testOpenNode(form);
        MsgSuccess(i18n.global.t('commons.msg.operationSuccess'));
    } finally {
        testLoading.value = false;
    }
};

const onDelete = async (row: Setting.OpenNodeItem) => {
    await ElMessageBox.confirm(i18n.global.t('commons.msg.delete'), i18n.global.t('commons.button.delete'), {
        confirmButtonText: i18n.global.t('commons.button.confirm'),
        cancelButtonText: i18n.global.t('commons.button.cancel'),
    });
    await deleteOpenNode(row.id);
    MsgSuccess(i18n.global.t('commons.msg.deleteSuccess'));
    search();
};

const onCheck = async (row: Setting.OpenNodeItem) => {
    loading.value = true;
    try {
        await testOpenNode({ id: row.id });
        MsgSuccess(i18n.global.t('commons.msg.operationSuccess'));
        search();
    } finally {
        loading.value = false;
    }
};

const buttons = [
    {
        label: i18n.global.t('commons.button.verify'),
        click: (row: Setting.OpenNodeItem) => onCheck(row),
    },
    {
        label: i18n.global.t('commons.button.edit'),
        click: (row: Setting.OpenNodeItem) => onOpenDialog(row),
    },
    {
        label: i18n.global.t('commons.button.delete'),
        click: (row: Setting.OpenNodeItem) => onDelete(row),
    },
];

onMounted(() => {
    search();
});
</script>
