<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import ApiClient from 'dashboard/api/ApiClient';
import { useAlert } from 'dashboard/composables';

const route = useRoute();
const { t } = useI18n();
const { currentAccount } = useAccount();
const api = new ApiClient('sales_documents', { accountScoped: true });
const document = ref(null);
const documentTypeLabel = computed(() => {
  if (document.value?.document_type === 'quotation')
    return t('SALES.QUOTATION');
  return t('SALES.INVOICE');
});

const loadDocument = async () => {
  try {
    const { data } = await api.show(route.params.documentId);
    document.value = data;
  } catch {
    useAlert(t('SALES.NOT_FOUND'));
  }
};

const formatMoney = (amount, currency) =>
  new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(
    amount
  );

const formatDate = value =>
  value ? new Date(value).toLocaleDateString() : '—';
const printDocument = () => window.print();

onMounted(loadDocument);
</script>

<template>
  <main
    class="mx-auto w-full max-w-4xl p-6 text-n-slate-12 print:fixed print:inset-0 print:z-50 print:max-w-none print:overflow-visible print:bg-white print:p-8"
  >
    <nav class="mb-6 flex items-center justify-between print:hidden">
      <router-link
        :to="{ name: 'sales_documents_index' }"
        class="text-sm font-medium text-n-brand"
      >
        {{ t('SALES.BACK') }}
      </router-link>
      <button
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white"
        @click="printDocument"
      >
        {{ t('SALES.PRINT_PDF') }}
      </button>
    </nav>
    <article
      v-if="document"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-8 print:border-0 print:bg-white print:p-0"
    >
      <header
        class="flex flex-wrap items-start justify-between gap-6 border-b border-n-weak pb-6"
      >
        <div>
          <p class="text-sm font-semibold uppercase tracking-wide text-n-brand">
            {{ currentAccount?.name }}
          </p>
          <h1 class="mt-2 text-3xl font-semibold">{{ documentTypeLabel }}</h1>
          <p class="mt-1 text-sm text-n-slate-11">{{ document.number }}</p>
        </div>
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <dt class="text-n-slate-11">{{ t('SALES.ISSUED') }}</dt>
          <dd>{{ formatDate(document.issue_date) }}</dd>
          <dt v-if="document.due_date" class="text-n-slate-11">
            {{ t('SALES.DUE_DATE') }}
          </dt>
          <dd v-if="document.due_date">{{ formatDate(document.due_date) }}</dd>
          <dt v-if="document.valid_until" class="text-n-slate-11">
            {{ t('SALES.VALID_UNTIL') }}
          </dt>
          <dd v-if="document.valid_until">
            {{ formatDate(document.valid_until) }}
          </dd>
        </dl>
      </header>

      <section class="py-6">
        <h2
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
        >
          {{ t('SALES.CUSTOMER_DETAILS') }}
        </h2>
        <p class="mt-2 font-medium">{{ document.customer_name }}</p>
        <p v-if="document.customer_email" class="text-sm text-n-slate-11">
          {{ document.customer_email }}
        </p>
        <p v-if="document.customer_phone" class="text-sm text-n-slate-11">
          {{ document.customer_phone }}
        </p>
      </section>

      <table class="w-full border-collapse text-left text-sm">
        <thead>
          <tr class="border-y border-n-weak text-n-slate-11">
            <th class="py-3">{{ t('SALES.ITEM') }}</th>
            <th class="py-3 text-right">{{ t('SALES.QUANTITY') }}</th>
            <th class="py-3 text-right">{{ t('SALES.UNIT_PRICE') }}</th>
            <th class="py-3 text-right">{{ t('SALES.TOTAL') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(item, index) in document.line_items"
            :key="index"
            class="border-b border-n-weak"
          >
            <td class="py-3">{{ item.description }}</td>
            <td class="py-3 text-right">{{ item.quantity }}</td>
            <td class="py-3 text-right">
              {{ formatMoney(item.unit_price, document.currency) }}
            </td>
            <td class="py-3 text-right">
              {{
                formatMoney(item.quantity * item.unit_price, document.currency)
              }}
            </td>
          </tr>
        </tbody>
      </table>

      <dl
        class="ml-auto mt-6 grid max-w-sm grid-cols-2 gap-x-8 gap-y-2 text-sm"
      >
        <dt class="text-n-slate-11">{{ t('SALES.SUBTOTAL') }}</dt>
        <dd class="text-right">
          {{ formatMoney(document.subtotal, document.currency) }}
        </dd>
        <dt class="text-n-slate-11">
          {{ t('SALES.TAX_RATE_LABEL', { rate: document.tax_rate }) }}
        </dt>
        <dd class="text-right">
          {{ formatMoney(document.tax_amount, document.currency) }}
        </dd>
        <dt class="border-t border-n-weak pt-3 font-semibold">
          {{ t('SALES.TOTAL') }}
        </dt>
        <dd class="border-t border-n-weak pt-3 text-right font-semibold">
          {{ formatMoney(document.total, document.currency) }}
        </dd>
      </dl>
      <p
        v-if="document.notes"
        class="mt-8 whitespace-pre-line border-t border-n-weak pt-5 text-sm"
      >
        {{ document.notes }}
      </p>
      <p class="mt-8 border-t border-n-weak pt-4 text-xs text-n-slate-10">
        {{ t('SALES.TAX_NOTICE') }}
      </p>
    </article>
  </main>
</template>
