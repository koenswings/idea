import { For } from "solid-js";

/** Real violation: index callback without a stable ID key (console.for_not_id_keyed). */
export function UnkeyedList(props) {
  return (
    <For each={props.items}>
      {(item, index) => <div>{item.name} #{index()}</div>}
    </For>
  );
}
