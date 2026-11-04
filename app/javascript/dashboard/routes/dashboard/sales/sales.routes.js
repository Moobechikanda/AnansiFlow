import { frontendURL } from '../../../helper/URLHelper';
import SalesDocuments from './SalesDocuments.vue';
import SalesDocumentPrint from './SalesDocumentPrint.vue';

export default [
  {
    path: frontendURL('accounts/:accountId/sales-documents'),
    name: 'sales_documents_index',
    component: SalesDocuments,
    meta: { permissions: ['administrator', 'agent'] },
  },
  {
    path: frontendURL('accounts/:accountId/sales-documents/:documentId/print'),
    name: 'sales_document_print',
    component: SalesDocumentPrint,
    meta: { permissions: ['administrator', 'agent'] },
  },
];
