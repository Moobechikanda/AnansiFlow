<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import ApiClient from 'dashboard/api/ApiClient';
import { useAlert } from 'dashboard/composables';
import axios from 'axios';
import { useI18n } from 'vue-i18n';

const api = new ApiClient('sales_documents', { accountScoped: true });
const documents = ref([]);
const loading = ref(false);
const saving = ref(false);
const recordingPayment = ref(false);
const paymentDocumentId = ref(null);
const paymentForm = ref({
  amount: '',
  provider: 'MTN',
  reference: '',
  paid_at: new Date().toLocaleDateString('en-CA'),
});
const { t } = useI18n();
const route = useRoute();
const type = ref('quotation');
const form = ref({
  customer_name: '',
  customer_phone: '',
  customer_email: '',
  currency: 'ZMW',
  tax_rate: 0,
  due_date: '',
  valid_until: '',
  notes: '',
  line_items: [{ description: '', quantity: 1, unit_price: 0 }],
});
const visibleDocuments = computed(() => documents.value);
const dueDate = computed({
  get: () =>
    type.value === 'quotation' ? form.value.valid_until : form.value.due_date,
  set: value => {
    if (type.value === 'quotation') form.value.valid_until = value;
    else form.value.due_date = value;
  },
});

const fetchDocuments = async () => {
  loading.value = true;
  try {
    const { data } = await api.get();
    documents.value = data;
  } catch {
    useAlert(t('SALES.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const addLine = () =>
  form.value.line_items.push({ description: '', quantity: 1, unit_price: 0 });

const createDocument = async () => {
  saving.value = true;
  try {
    await api.create({
      sales_document: { ...form.value, document_type: type.value },
    });
    useAlert(
      type.value === 'quotation'
        ? t('SALES.QUOTATION_CREATED')
        : t('SALES.INVOICE_CREATED')
    );
    form.value.customer_name = '';
    form.value.customer_phone = '';
    form.value.customer_email = '';
    form.value.line_items = [{ description: '', quantity: 1, unit_price: 0 }];
    await fetchDocuments();
  } catch (error) {
    useAlert(error.response?.data?.message || t('SALES.CREATE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const updateStatus = async (document, status) => {
  try {
    await api.update(document.id, { sales_document: { status } });
    await fetchDocuments();
  } catch {
    useAlert(t('SALES.UPDATE_ERROR'));
  }
};

const convertToInvoice = async document => {
  try {
    await axios.post(`${api.url}/${document.id}/convert`);
    await fetchDocuments();
    useAlert(t('SALES.CONVERTED'));
  } catch {
    useAlert(t('SALES.CONVERT_ERROR'));
  }
};

const recordPayment = async document => {
  recordingPayment.value = true;
  try {
    await axios.post(`${api.url}/${document.id}/payments`, {
      payment: {
        ...paymentForm.value,
        method: 'mobile_money',
      },
    });
    paymentDocumentId.value = null;
    paymentForm.value = {
      amount: '',
      provider: 'MTN',
      reference: '',
      paid_at: new Date().toLocaleDateString('en-CA'),
    };
    await fetchDocuments();
  } catch {
    useAlert(t('SALES.PAYMENT_ERROR'));
  } finally {
    recordingPayment.value = false;
  }
};

const openPaymentForm = document => {
  paymentDocumentId.value =
    paymentDocumentId.value === document.id ? null : document.id;
  paymentForm.value = {
    amount: document.outstanding_amount,
    provider: 'MTN',
    reference: '',
    paid_at: new Date().toLocaleDateString('en-CA'),
  };
};

const formatMoney = (amount, currency) =>
  new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(
    amount
  );

const documentTypeLabel = document => {
  if (document.document_type === 'quotation') return t('SALES.QUOTATION');
  return t('SALES.INVOICE');
};

const documentSummary = document =>
  t('SALES.DOCUMENT_STATUS', {
    type: documentTypeLabel(document),
    status: document.status.replace('_', ' '),
    total: formatMoney(document.total, document.currency),
  });

const paymentSummary = document =>
  t('SALES.PAYMENT_SUMMARY', {
    payments: document.payments
      .map(
        payment =>
          `${payment.provider || payment.method} ${formatMoney(payment.amount, document.currency)} ${payment.reference || ''}`
      )
      .join(', '),
  });

const dueDateLabel = () => {
  if (type.value === 'quotation') return t('SALES.VALID_UNTIL');
  return t('SALES.DUE_DATE');
};

const createButtonLabel = () => {
  if (type.value === 'quotation') return t('SALES.CREATE_QUOTATION');
  return t('SALES.CREATE_INVOICE');
};

const whatsappUrl = document => {
  const digits = (document.customer_phone || '').replace(/\D/g, '');
  let phone = digits;
  if (digits.startsWith('0')) phone = `260${digits.slice(1)}`;
  else if (!digits.startsWith('260')) phone = `260${digits}`;
  const items = document.line_items
    .map(item => `${item.quantity} × ${item.description}`)
    .join(', ');
  const documentType = documentTypeLabel(document);
  const text = `${documentType} ${document.number}: ${items}. Total ${formatMoney(document.total, document.currency)}. ${t('SALES.PAYMENT_MESSAGE')}`;
  return `https://wa.me/${phone}?text=${encodeURIComponent(text)}`;
};

onMounted(fetchDocuments);
</script>

<template>
  <main class="mx-auto flex w-full max-w-7xl flex-col gap-6 p-6">
    <header>
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ t('SALES.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">{{ t('SALES.INTRO') }}</p>
    </header>

    <section class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
      <h2 class="mb-4 text-lg font-medium text-n-slate-12">
        {{ t('SALES.CREATE') }}
      </h2>
      <form class="flex flex-col gap-4" @submit.prevent="createDocument">
        <div class="grid gap-4 md:grid-cols-2">
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.TYPE') }}
            <select
              v-model="type"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            >
              <option value="quotation">{{ t('SALES.QUOTATION') }}</option>
              <option value="invoice">{{ t('SALES.INVOICE') }}</option>
            </select>
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.CUSTOMER') }}
            <input
              v-model.trim="form.customer_name"
              required
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.PHONE') }}
            <input
              v-model.trim="form.customer_phone"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
              :placeholder="t('SALES.PHONE_PLACEHOLDER')"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.EMAIL') }}
            <input
              v-model.trim="form.customer_email"
              type="email"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
          </label>
        </div>

        <div class="flex flex-col gap-3">
          <div
            v-for="(item, index) in form.line_items"
            :key="index"
            class="grid gap-3 md:grid-cols-[1fr_8rem_10rem]"
          >
            <input
              v-model.trim="item.description"
              required
              :aria-label="t('SALES.ITEM')"
              :placeholder="t('SALES.ITEM')"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
            <input
              v-model.number="item.quantity"
              required
              min="0.01"
              step="0.01"
              type="number"
              :aria-label="t('SALES.QUANTITY')"
              :placeholder="t('SALES.QUANTITY')"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
            <input
              v-model.number="item.unit_price"
              required
              min="0"
              step="0.01"
              type="number"
              :aria-label="t('SALES.UNIT_PRICE')"
              :placeholder="
                t('SALES.UNIT_PRICE_CURRENCY', { currency: form.currency })
              "
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
          </div>
          <button
            type="button"
            class="self-start text-sm font-medium text-n-brand"
            @click="addLine"
          >
            {{ t('SALES.ADD_ITEM') }}
          </button>
        </div>

        <div class="grid gap-4 md:grid-cols-3">
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.CURRENCY') }}
            <input
              v-model.trim="form.currency"
              required
              maxlength="3"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 uppercase text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ t('SALES.TAX_RATE') }}
            <input
              v-model.number="form.tax_rate"
              type="number"
              min="0"
              max="100"
              step="0.01"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-11">
            {{ dueDateLabel() }}
            <input
              v-model="dueDate"
              type="date"
              class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
            />
          </label>
        </div>
        <textarea
          v-model.trim="form.notes"
          rows="2"
          :placeholder="t('SALES.NOTES')"
          class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-n-slate-12"
        />
        <p class="text-xs text-n-slate-10">{{ t('SALES.TAX_NOTICE') }}</p>
        <button
          :disabled="saving"
          type="submit"
          class="self-start rounded-lg bg-n-brand px-4 py-2 font-medium text-white disabled:opacity-50"
        >
          {{ saving ? t('SALES.SAVING') : createButtonLabel() }}
        </button>
      </form>
    </section>

    <section
      class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
    >
      <div class="border-b border-n-weak px-5 py-4">
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('SALES.RECENT') }}
        </h2>
      </div>
      <p v-if="loading" class="p-5 text-sm text-n-slate-11">
        {{ t('SALES.LOADING') }}
      </p>
      <p
        v-else-if="!visibleDocuments.length"
        class="p-5 text-sm text-n-slate-11"
      >
        {{ t('SALES.EMPTY') }}
      </p>
      <div v-else class="divide-y divide-n-weak">
        <article
          v-for="document in visibleDocuments"
          :key="document.id"
          class="flex flex-col gap-3 p-5 md:flex-row md:items-center md:justify-between"
        >
          <div>
            <p class="font-medium text-n-slate-12">
              {{
                t('SALES.DOCUMENT_TITLE', {
                  number: document.number,
                  customer: document.customer_name,
                })
              }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ documentSummary(document) }}
              <span v-if="document.document_type === 'invoice'">
                {{
                  t('SALES.DOCUMENT_DUE', {
                    amount: formatMoney(
                      document.outstanding_amount,
                      document.currency
                    ),
                  })
                }}
              </span>
            </p>
            <p
              v-if="document.payments?.length"
              class="mt-1 text-xs text-n-slate-10"
            >
              {{ paymentSummary(document) }}
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <router-link
              :to="{
                name: 'sales_document_print',
                params: {
                  accountId: route.params.accountId,
                  documentId: document.id,
                },
              }"
              target="_blank"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm text-n-slate-12"
            >
              {{ t('SALES.PRINT_PDF') }}
            </router-link>
            <a
              v-if="document.customer_phone"
              :href="whatsappUrl(document)"
              target="_blank"
              rel="noopener noreferrer"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm text-n-slate-12"
            >
              {{ t('SALES.SHARE_WHATSAPP') }}
            </a>
            <select
              v-if="document.document_type === 'quotation'"
              :value="document.status"
              class="rounded-lg border border-n-weak bg-n-background px-2 py-1.5 text-sm text-n-slate-12"
              @change="updateStatus(document, $event.target.value)"
            >
              <option value="draft" disabled>{{ t('SALES.DRAFT') }}</option>
              <option value="sent">{{ t('SALES.SENT') }}</option>
              <option value="accepted" :disabled="document.status !== 'sent'">
                {{ t('SALES.ACCEPTED') }}
              </option>
              <option value="declined" :disabled="document.status !== 'sent'">
                {{ t('SALES.DECLINED') }}
              </option>
            </select>
            <button
              v-if="
                document.document_type === 'quotation' &&
                document.status === 'accepted'
              "
              type="button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm text-n-slate-12"
              @click="convertToInvoice(document)"
            >
              {{ t('SALES.CONVERT') }}
            </button>
            <button
              v-if="
                document.document_type === 'invoice' &&
                document.status !== 'paid' &&
                document.status !== 'void'
              "
              type="button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm text-n-slate-12"
              @click="openPaymentForm(document)"
            >
              {{ t('SALES.RECORD_PAYMENT') }}
            </button>
          </div>
          <form
            v-if="paymentDocumentId === document.id"
            class="grid gap-3 rounded-lg bg-n-slate-2 p-4 md:grid-cols-4"
            @submit.prevent="recordPayment(document)"
          >
            <p class="text-xs text-n-slate-10 md:col-span-4">
              {{ t('SALES.PAYMENT_VERIFY_NOTICE') }}
            </p>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{
                t('SALES.PAYMENT_AMOUNT_CURRENCY', {
                  currency: document.currency,
                })
              }}
              <input
                v-model.number="paymentForm.amount"
                required
                type="number"
                min="0.01"
                :max="document.outstanding_amount"
                step="0.01"
                class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12"
              />
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('SALES.PAYMENT_PROVIDER_LABEL') }}
              <select
                v-model="paymentForm.provider"
                required
                class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12"
              >
                <option value="MTN">{{ t('SALES.PROVIDER_MTN') }}</option>
                <option value="Airtel">{{ t('SALES.PROVIDER_AIRTEL') }}</option>
                <option value="Zamtel">{{ t('SALES.PROVIDER_ZAMTEL') }}</option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('SALES.PAYMENT_REFERENCE_LABEL') }}
              <input
                v-model.trim="paymentForm.reference"
                class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12"
              />
            </label>
            <label class="flex flex-col gap-1 text-xs text-n-slate-11">
              {{ t('SALES.PAYMENT_DATE') }}
              <input
                v-model="paymentForm.paid_at"
                required
                type="date"
                class="rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12"
              />
            </label>
            <div class="flex items-center gap-2 md:col-span-4">
              <button
                :disabled="recordingPayment"
                type="submit"
                class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
              >
                {{
                  recordingPayment
                    ? t('SALES.RECORDING')
                    : t('SALES.RECORD_PAYMENT')
                }}
              </button>
              <button
                type="button"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
                @click="paymentDocumentId = null"
              >
                {{ t('SALES.CANCEL') }}
              </button>
            </div>
          </form>
        </article>
      </div>
    </section>
  </main>
</template>
