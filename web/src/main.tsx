import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import Storefront from './components/Storefront'
import './index.css'

// A ?store=<tenantId> link opens the public customer storefront (no login);
// everything else is the staff/owner app.
const storeTenant = new URLSearchParams(window.location.search).get('store')

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {storeTenant ? <Storefront tenantId={storeTenant} /> : <App />}
  </React.StrictMode>,
)
