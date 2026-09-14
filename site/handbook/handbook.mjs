import contract from './contract.mjs';

const output = document.querySelector('#event-output');
const buttons = [...document.querySelectorAll('[data-event]')];
function text(tag, value, className) {
  const element = document.createElement(tag);
  element.textContent = value;
  if (className) element.className = className;
  return element;
}
for (const button of buttons) button.addEventListener('click', () => {
  const event = contract.events.find(item => item.id === button.dataset.event);
  if (!event || !output) return;
  const panel = text('div', '', 'event-result');
  panel.append(text('h3', event.label), text('span', event.status === 'proposed' ? 'Proposed behavior' : 'Implemented behavior', `status ${event.status}`));
  const columns = text('div', '', 'event-columns');
  for (const [label, value] of [['Stops or changes', event.stops], ['Keeps', event.keeps]]) {
    const column = text('div', ''); column.append(text('h4', label), text('p', value)); columns.append(column);
  }
  panel.append(columns, text('p', event.check, 'event-check'));
  output.replaceChildren(panel);
  for (const item of buttons) item.setAttribute('aria-pressed', String(item === button));
});
