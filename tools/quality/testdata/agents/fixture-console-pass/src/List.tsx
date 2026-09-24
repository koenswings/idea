import { For, createMemo } from "solid-js";

export function List(props) {
  // Stable 1-based step IDs so <For> keys by ID, not array index.
  // (idea#61: comment text must not open a <For> match for the bake-in)
  const stepIds = createMemo(() =>
    Array.from({ length: props.totalSteps ?? 0 }, (_, i) => i + 1)
  );

  return (
    <>
      {/* Example: <For each={xs}>{(x, i) => ...}</For> must stay a comment */}
      <For each={stepIds()}>
        {(stepId) => <div>{stepId}</div>}
      </For>
      <For each={props.items}>
        {(item) => <div>{item.name}</div>}
      </For>
    </>
  );
}
