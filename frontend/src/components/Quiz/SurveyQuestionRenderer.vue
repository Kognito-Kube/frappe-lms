<template>
	<div class="space-y-4" data-testid="surveyjs-renderer">
		<div
			v-if="!elements.length"
			class="rounded-6 border border-dashed border-outline-gray-2 p-4 text-sm text-ink-gray-5"
		>
			{{ __('Provide a valid SurveyJS JSON schema to render this question.') }}
		</div>

		<div
			v-for="(el, elIdx) in elements"
			:key="el.name || elIdx"
			class="space-y-2.5 rounded-6 border border-outline-gray-2 bg-surface-base p-3.5"
		>
			<div v-if="el.title || el.description" class="space-y-0.5">
				<div
					v-if="el.title"
					class="text-sm font-medium text-ink-gray-9"
				>
					{{ el.title }}
					<span v-if="el.isRequired" class="text-ink-red-5">*</span>
				</div>
				<div v-if="el.description" class="text-xs text-ink-gray-6">
					{{ el.description }}
				</div>
			</div>

			<!-- 1. RANKING (Order items with up/down controls + drag support) -->
			<div v-if="el.type === 'ranking'" class="space-y-1.5">
				<div
					v-for="(item, idx) in getRankingList(el)"
					:key="item.value"
					draggable="true"
					@dragstart="!disabled && onDragStart(el, idx)"
					@dragover.prevent
					@drop="!disabled && onDrop(el, idx)"
					class="flex items-center justify-between gap-3 rounded-4 border border-outline-gray-2 bg-surface-gray-1 px-3 py-2 text-sm text-ink-gray-9 transition"
					:class="
						disabled
							? 'opacity-75'
							: 'cursor-grab hover:border-outline-gray-4 active:cursor-grabbing'
					"
				>
					<div class="flex items-center gap-2.5 min-w-0">
						<span
							class="flex size-5 shrink-0 items-center justify-center rounded-full bg-surface-gray-3 text-xs font-semibold text-ink-gray-8"
						>
							{{ idx + 1 }}
						</span>
						<span class="truncate">{{ item.text }}</span>
					</div>
					<div v-if="!disabled" class="flex items-center gap-1 shrink-0">
						<button
							type="button"
							class="rounded p-1 text-ink-gray-6 hover:bg-surface-gray-3 hover:text-ink-gray-9 disabled:opacity-30"
							:disabled="idx === 0"
							:aria-label="__('Move up')"
							@click="moveRankingItem(el, idx, -1)"
						>
							<span class="lucide-arrow-up size-3.5 block" />
						</button>
						<button
							type="button"
							class="rounded p-1 text-ink-gray-6 hover:bg-surface-gray-3 hover:text-ink-gray-9 disabled:opacity-30"
							:disabled="idx === getRankingList(el).length - 1"
							:aria-label="__('Move down')"
							@click="moveRankingItem(el, idx, 1)"
						>
							<span class="lucide-arrow-down size-3.5 block" />
						</button>
					</div>
				</div>
			</div>

			<!-- 2. MATRIX (Single-choice grid per row) -->
			<div v-else-if="el.type === 'matrix'" class="overflow-x-auto">
				<table class="w-full border-collapse text-left text-sm">
					<thead>
						<tr class="border-b border-outline-gray-2 text-xs text-ink-gray-6">
							<th class="py-2 pe-3 font-medium"></th>
							<th
								v-for="col in normalizeChoices(el.columns)"
								:key="col.value"
								class="px-3 py-2 text-center font-medium"
							>
								{{ col.text }}
							</th>
						</tr>
					</thead>
					<tbody class="divide-y divide-outline-gray-1">
						<tr
							v-for="row in normalizeChoices(el.rows)"
							:key="row.value"
							class="hover:bg-surface-gray-1"
						>
							<td class="py-2.5 pe-3 font-medium text-ink-gray-8">
								{{ row.text }}
							</td>
							<td
								v-for="col in normalizeChoices(el.columns)"
								:key="col.value"
								class="px-3 py-2.5 text-center"
							>
								<input
									type="radio"
									:name="`matrix-${uid}-${el.name}-${row.value}`"
									:disabled="disabled"
									:checked="getMatrixValue(el.name, row.value) === col.value"
									class="size-4 border-outline-gray-4 text-ink-gray-9 focus:ring-0"
									@change="setMatrixValue(el.name, row.value, col.value)"
								/>
							</td>
						</tr>
					</tbody>
				</table>
			</div>

			<!-- 3. RATING (Numeric / scale pills) -->
			<div v-else-if="el.type === 'rating'" class="space-y-2">
				<div class="flex flex-wrap items-center gap-2">
					<span
						v-if="el.minRateDescription"
						class="text-xs text-ink-gray-6 me-1"
					>
						{{ el.minRateDescription }}
					</span>
					<button
						v-for="rate in getRatingValues(el)"
						:key="rate.value"
						type="button"
						:disabled="disabled"
						class="flex h-9 min-w-[2.25rem] items-center justify-center rounded-4 border px-2.5 text-sm font-medium transition"
						:class="
							responses[el.name] === rate.value
								? 'border-ink-gray-9 bg-surface-gray-7 text-ink-base'
								: 'border-outline-gray-2 bg-surface-base text-ink-gray-8 hover:bg-surface-gray-2'
						"
						@click="setElementValue(el.name, rate.value)"
					>
						{{ rate.text }}
					</button>
					<span
						v-if="el.maxRateDescription"
						class="text-xs text-ink-gray-6 ms-1"
					>
						{{ el.maxRateDescription }}
					</span>
				</div>
			</div>

			<!-- 4. BOOLEAN (Yes / No toggle buttons) -->
			<div v-else-if="el.type === 'boolean'" class="flex items-center gap-2">
				<button
					type="button"
					:disabled="disabled"
					class="rounded-4 border px-4 py-2 text-sm font-medium transition"
					:class="
						responses[el.name] === true
							? 'border-ink-gray-9 bg-surface-gray-7 text-ink-base'
							: 'border-outline-gray-2 bg-surface-base text-ink-gray-8 hover:bg-surface-gray-2'
					"
					@click="setElementValue(el.name, true)"
				>
					{{ el.labelTrue || __('Yes') }}
				</button>
				<button
					type="button"
					:disabled="disabled"
					class="rounded-4 border px-4 py-2 text-sm font-medium transition"
					:class="
						responses[el.name] === false
							? 'border-ink-gray-9 bg-surface-gray-7 text-ink-base'
							: 'border-outline-gray-2 bg-surface-base text-ink-gray-8 hover:bg-surface-gray-2'
					"
					@click="setElementValue(el.name, false)"
				>
					{{ el.labelFalse || __('No') }}
				</button>
			</div>

			<!-- 5. MULTIPLETEXT (Fill-in-the-blanks / multiple labeled inputs) -->
			<div v-else-if="el.type === 'multipletext'" class="grid gap-3 sm:grid-cols-2">
				<div
					v-for="item in el.items || []"
					:key="item.name"
					class="space-y-1"
				>
					<label class="block text-xs font-medium text-ink-gray-7">
						{{ item.title || item.name }}
					</label>
					<FormControl
						type="text"
						variant="outline"
						:disabled="disabled"
						:placeholder="item.placeholder || ''"
						:model-value="getMultiTextValue(el.name, item.name)"
						@update:model-value="
							(val) => setMultiTextValue(el.name, item.name, val)
						"
					/>
				</div>
			</div>

			<!-- 6. RADIOGROUP / DROPDOWN -->
			<div
				v-else-if="el.type === 'radiogroup' || el.type === 'dropdown'"
				class="space-y-1.5"
			>
				<label
					v-for="choice in normalizeChoices(el.choices)"
					:key="choice.value"
					class="flex cursor-pointer items-center gap-2.5 rounded-4 border border-outline-gray-2 px-3 py-2 text-sm text-ink-gray-9 hover:bg-surface-gray-1"
				>
					<input
						type="radio"
						:name="`radio-${uid}-${el.name}`"
						:disabled="disabled"
						:checked="responses[el.name] === choice.value"
						class="size-4 border-outline-gray-4 text-ink-gray-9 focus:ring-0"
						@change="setElementValue(el.name, choice.value)"
					/>
					<span>{{ choice.text }}</span>
				</label>
			</div>

			<!-- 7. CHECKBOX -->
			<div v-else-if="el.type === 'checkbox'" class="space-y-1.5">
				<label
					v-for="choice in normalizeChoices(el.choices)"
					:key="choice.value"
					class="flex cursor-pointer items-center gap-2.5 rounded-4 border border-outline-gray-2 px-3 py-2 text-sm text-ink-gray-9 hover:bg-surface-gray-1"
				>
					<input
						type="checkbox"
						:disabled="disabled"
						:checked="isCheckboxChecked(el.name, choice.value)"
						class="size-4 rounded-1 border-outline-gray-4 text-ink-gray-9 focus:ring-0"
						@change="toggleCheckbox(el.name, choice.value)"
					/>
					<span>{{ choice.text }}</span>
				</label>
			</div>

			<!-- 8. TEXT / COMMENT fallback -->
			<div v-else>
				<FormControl
					:type="el.type === 'comment' ? 'textarea' : 'text'"
					variant="outline"
					:disabled="disabled"
					:placeholder="el.placeholder || __('Enter your answer')"
					:model-value="responses[el.name] ?? ''"
					@update:model-value="(val) => setElementValue(el.name, val)"
				/>
			</div>
		</div>
	</div>
</template>

<script setup>
import { FormControl } from 'frappe-ui'
import { computed, reactive, ref, useId, watch } from 'vue'

const props = defineProps({
	surveyJson: { type: String, default: '' },
	modelValue: { type: String, default: '' },
	disabled: { type: Boolean, default: false },
})

const emit = defineEmits(['update:modelValue'])
const uid = useId()

const responses = reactive({})
const dragSourceIdx = ref(null)

const normalizeChoices = (list) => {
	if (!Array.isArray(list)) return []
	return list.map((item) => {
		if (item && typeof item === 'object') {
			const val = item.value ?? item.name ?? item.text ?? ''
			return {
				value: String(val),
				text: String(item.text ?? item.title ?? val),
			}
		}
		return { value: String(item), text: String(item) }
	})
}

const elements = computed(() => {
	if (!props.surveyJson) return []
	try {
		const parsed = JSON.parse(props.surveyJson)
		if (!parsed || typeof parsed !== 'object') return []
		let raw = []
		if (Array.isArray(parsed.elements)) {
			raw = parsed.elements
		} else if (Array.isArray(parsed.pages)) {
			for (const page of parsed.pages) {
				if (Array.isArray(page?.elements)) raw.push(...page.elements)
			}
		} else if (parsed.type) {
			raw = [parsed]
		}
		return raw
			.filter((el) => el && typeof el === 'object' && el.type)
			.map((el, idx) => ({
				...el,
				name: el.name || `q${idx + 1}`,
			}))
	} catch {
		return []
	}
})

const syncFromModelValue = () => {
	Object.keys(responses).forEach((k) => delete responses[k])
	if (props.modelValue) {
		try {
			const parsed = JSON.parse(props.modelValue)
			if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
				Object.assign(responses, parsed)
			}
		} catch {
			// Ignore malformed JSON while typing
		}
	}
	// Seed ranking questions with their initial choice order if not yet interacted with
	for (const el of elements.value) {
		if (el.type === 'ranking' && !Array.isArray(responses[el.name])) {
			const choices = normalizeChoices(el.choices)
			if (choices.length) {
				responses[el.name] = choices.map((c) => c.value)
			}
		}
	}
}

watch(
	() => [props.surveyJson, props.modelValue],
	() => syncFromModelValue(),
	{ immediate: true }
)

const emitChange = () => {
	emit('update:modelValue', JSON.stringify(responses))
}

const setElementValue = (name, value) => {
	responses[name] = value
	emitChange()
}

// Ranking helpers
const getRankingList = (el) => {
	const choices = normalizeChoices(el.choices)
	const byValue = Object.fromEntries(choices.map((c) => [c.value, c]))
	const currentOrder = Array.isArray(responses[el.name])
		? responses[el.name].map(String)
		: choices.map((c) => c.value)
	const ordered = currentOrder.map((v) => byValue[v]).filter(Boolean)
	for (const c of choices) {
		if (!ordered.some((o) => o.value === c.value)) ordered.push(c)
	}
	return ordered
}

const moveRankingItem = (el, idx, delta) => {
	const list = getRankingList(el).map((i) => i.value)
	const target = idx + delta
	if (target < 0 || target >= list.length) return
	const [moved] = list.splice(idx, 1)
	list.splice(target, 0, moved)
	responses[el.name] = list
	emitChange()
}

const onDragStart = (el, idx) => {
	dragSourceIdx.value = { name: el.name, idx }
}

const onDrop = (el, targetIdx) => {
	if (!dragSourceIdx.value || dragSourceIdx.value.name !== el.name) return
	const fromIdx = dragSourceIdx.value.idx
	dragSourceIdx.value = null
	if (fromIdx === targetIdx) return
	const list = getRankingList(el).map((i) => i.value)
	const [moved] = list.splice(fromIdx, 1)
	list.splice(targetIdx, 0, moved)
	responses[el.name] = list
	emitChange()
}

// Matrix helpers
const getMatrixValue = (elName, rowKey) => {
	const mat = responses[elName]
	if (!mat || typeof mat !== 'object') return undefined
	return mat[rowKey]
}

const setMatrixValue = (elName, rowKey, colVal) => {
	const current =
		responses[elName] && typeof responses[elName] === 'object'
			? { ...responses[elName] }
			: {}
	current[rowKey] = colVal
	responses[elName] = current
	emitChange()
}

// Rating helpers
const getRatingValues = (el) => {
	if (Array.isArray(el.rateValues) && el.rateValues.length) {
		return normalizeChoices(el.rateValues)
	}
	const min = Number.isFinite(Number(el.rateMin)) ? Number(el.rateMin) : 1
	const max = Number.isFinite(Number(el.rateMax)) ? Number(el.rateMax) : 5
	const step =
		Number.isFinite(Number(el.rateStep)) && Number(el.rateStep) > 0
			? Number(el.rateStep)
			: 1
	const vals = []
	for (let v = min; v <= max; v += step) {
		vals.push({ value: v, text: String(v) })
	}
	return vals
}

// Multiple Text helpers
const getMultiTextValue = (elName, itemName) => {
	const obj = responses[elName]
	if (!obj || typeof obj !== 'object') return ''
	return obj[itemName] ?? ''
}

const setMultiTextValue = (elName, itemName, val) => {
	const current =
		responses[elName] && typeof responses[elName] === 'object'
			? { ...responses[elName] }
			: {}
	current[itemName] = val
	responses[elName] = current
	emitChange()
}

// Checkbox helpers
const isCheckboxChecked = (elName, choiceVal) => {
	const arr = responses[elName]
	return Array.isArray(arr) && arr.includes(choiceVal)
}

const toggleCheckbox = (elName, choiceVal) => {
	const arr = Array.isArray(responses[elName]) ? [...responses[elName]] : []
	const idx = arr.indexOf(choiceVal)
	if (idx >= 0) arr.splice(idx, 1)
	else arr.push(choiceVal)
	responses[elName] = arr
	emitChange()
}
</script>
