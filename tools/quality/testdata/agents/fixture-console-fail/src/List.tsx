import { For } from "solid-js";
import { useStore } from "./store";

const state = useStore(store);

export function List(props) {
  return (
    <For each={props.items}>
      {(item, index) => <div key={index}>{item.name}</div>}
    </For>
  );
}

const css = "https://unpkg.com/bootstrap@5/dist/css/bootstrap.min.css";
