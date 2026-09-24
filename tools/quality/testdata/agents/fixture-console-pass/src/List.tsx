import { For } from "solid-js";

export function List(props) {
  return (
    <For each={props.items}>
      {(item) => <div>{item.name}</div>}
    </For>
  );
}
